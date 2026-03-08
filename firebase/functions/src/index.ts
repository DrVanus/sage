/**
 * CryptoSage AI - Firebase Cloud Functions
 * 
 * This module provides secure API proxying and caching for:
 * - OpenAI AI insights (market sentiment, coin analysis, predictions)
 * - CoinGecko market data with rate limit management
 * - User authentication and subscription validation
 * 
 * SECURITY FEATURES:
 * - Input validation and sanitization
 * - Rate limiting per IP and user
 * - Audit logging for security events
 * - App Check verification (optional)
 * - Subscription verification
 */

import * as admin from "firebase-admin";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2/options";
import OpenAI from "openai";
// @ts-ignore - google-trends-api doesn't have types
import googleTrends from "google-trends-api";

// Security utilities
import {
  sanitizeString,
  validateCoinSymbol,
  validateCoinId,
  validateTimeframe,
  validateHoldings,
  validateNumber,
  checkRateLimit,
  logAuditEvent,
  verifySubscription,
  getTierLimits,
  safeError,
  getClientIP,
} from "./security";

// Technical indicators
import {
  computeTechnicalsSummary,
  computeBasicTechnicalsSummary,
  fetchBinanceCandles,
  fetchCoinbaseCandles,
  generateAISummary,
  type TechnicalsSummary,
} from "./technicals";

// Logging and resilience utilities
// Note: These are exported for use in individual functions
// Use createLogger(functionName) for structured logging
// Use withRetry(fn, RETRY_PRESETS.openai) for retry with backoff
export { createLogger, Logger, withLogging } from "./logging";
export { withRetry, withResiliency, RETRY_PRESETS } from "./retry";

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();

// ============================================================================
// GLOBAL OPTIONS
// ============================================================================

// APP CHECK CONFIGURATION
// =======================
// App Check protects Cloud Functions from unauthorized access by verifying
// that requests come from your authentic iOS app, not from scrapers or bots.
//
// SETUP:
// 1. Configure App Check in iOS app (see AppCheckManager.swift)
// 2. For testing: Register debug tokens in Firebase Console
// 3. For production: Register App Attest in Firebase Console
// 4. Enable enforcement: firebase functions:config:set runtime.enable_app_check=true
// 5. Deploy: firebase deploy --only functions
//
// ENVIRONMENT VARIABLES:
// - runtime.enable_app_check: "true" to enable, "false" to disable
// - runtime.node_env: "production" or "development"
//
// NOTE: App Check is recommended for production to prevent API abuse.
// In development, use debug tokens (valid for 7 days).
// App Check is OPT-IN: set ENABLE_APP_CHECK=true to enforce.
// Without proper setup (registered debug tokens or App Attest),
// enforcing App Check will reject ALL callable requests.
const ENFORCE_APP_CHECK = process.env.ENABLE_APP_CHECK === "true";

// Set global options for all functions
setGlobalOptions({
  maxInstances: 10,
  region: "us-central1",
  // App Check prevents unauthorized API access from non-app clients
  // Opt-in only: set ENABLE_APP_CHECK=true after configuring App Check in Firebase Console
  enforceAppCheck: ENFORCE_APP_CHECK,
});

// Performance: Memory tier configuration for different function types
// Usage: memory: FUNCTION_MEMORY.heavy for AI operations
export const FUNCTION_MEMORY = {
  light: "256MiB" as const,    // Simple operations (health checks, cache reads)
  standard: "512MiB" as const, // Market data, moderate processing
  heavy: "1GiB" as const,      // AI operations, complex calculations
} as const;

// ============================================================================
// CONFIGURATION
// ============================================================================

const CACHE_DURATIONS = {
  marketSentiment: 60 * 60 * 1000,      // 1 hour
  cryptoSageAISentiment: 5 * 60 * 1000, // 5 minutes - matches prewarm schedule
  coinInsight: 2 * 60 * 60 * 1000,      // 2 hours
  priceMovementExplanation: 2 * 60 * 60 * 1000, // 2 hours - "Why is it moving?" explanations
  prediction: 30 * 60 * 1000,           // 30 minutes (shorter for fresher predictions)
  technicalSummary: 30 * 60 * 1000,     // 30 minutes
  fearGreedCommentary: 6 * 60 * 60 * 1000, // 6 hours
  coinGeckoMarkets: 5 * 60 * 1000,      // 5 minutes
  coinGeckoGlobal: 10 * 60 * 1000,      // 10 minutes
  binanceTickers: 30 * 1000,            // 30 seconds - for real-time prices
  coinImage: 7 * 24 * 60 * 60 * 1000,   // 7 days - coin images rarely change
  tradingSignal: 30 * 60 * 1000,        // 30 minutes - AI trading signals
};

// Coin image configuration
const COIN_IMAGE_CONFIG = {
  storagePath: "coin-images",
  syncBatchSize: 50,         // Process 50 coins at a time to avoid timeouts
  maxCoinsToSync: 500,       // Sync top 500 coins by market cap
  imageSources: [
    { name: "coingecko", priority: 1 },
    { name: "coincap", priority: 2 },
    { name: "cryptoicons", priority: 3 },
  ],
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Get OpenAI client with API key from Firebase config
 */
function getOpenAIClient(): OpenAI {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "OpenAI API key not configured");
  }
  return new OpenAI({ apiKey, fetch: globalThis.fetch });
}

/**
 * Get the best available AI client for crypto predictions.
 * 
 * Priority chain (best to worst for crypto predictions):
 * 1. DeepSeek Direct API (DEEPSEEK_API_KEY) - Alpha Arena winner: +116% return
 * 2. OpenRouter Free DeepSeek (OPENROUTER_API_KEY) - Same model, $0 cost via free tier
 * 3. OpenAI GPT-4.1-mini (OPENAI_API_KEY) - Fallback, worst for crypto but always available
 * 
 * DeepSeek V3.2 uses an OpenAI-compatible API, so we use the OpenAI SDK with custom baseURL.
 */
function getDeepSeekClient(): { client: OpenAI; model: string; provider: string } {
  // Use native fetch — SDK's built-in HTTP client fails on Cloud Run
  const fetchFn = globalThis.fetch;

  // Priority 1: DeepSeek Direct API (best performance, ~$0.28/1M tokens)
  const deepseekKey = process.env.DEEPSEEK_API_KEY;
  if (deepseekKey) {
    return {
      client: new OpenAI({ apiKey: deepseekKey, baseURL: "https://api.deepseek.com/v1", timeout: 30000, maxRetries: 1, fetch: fetchFn }),
      model: "deepseek-chat", // DeepSeek V3.2 (auto-resolves to latest)
      provider: "deepseek",
    };
  }

  // Priority 2: OpenRouter Free DeepSeek (same model, $0 cost)
  const openrouterKey = process.env.OPENROUTER_API_KEY;
  if (openrouterKey) {
    console.log("[getDeepSeekClient] Using OpenRouter free tier for DeepSeek predictions");
    return {
      client: new OpenAI({
        apiKey: openrouterKey,
        baseURL: "https://openrouter.ai/api/v1",
        timeout: 30000,
        maxRetries: 1,
        fetch: fetchFn,
        defaultHeaders: {
          "HTTP-Referer": "https://cryptosage.app",
          "X-Title": "CryptoSage",
        },
      }),
      model: "deepseek/deepseek-chat:free", // Free tier DeepSeek V3 on OpenRouter
      provider: "openrouter-deepseek-free",
    };
  }
  
  // Priority 3: OpenAI GPT-4.1-mini fallback (worst for crypto, but always available)
  console.log("[getDeepSeekClient] No DeepSeek or OpenRouter key, falling back to OpenAI gpt-4.1-mini");
  const openaiKey = process.env.OPENAI_API_KEY;
  if (!openaiKey) {
    throw new HttpsError("failed-precondition", "No AI API key configured (tried DEEPSEEK_API_KEY, OPENROUTER_API_KEY, OPENAI_API_KEY)");
  }
  return {
    client: new OpenAI({ apiKey: openaiKey, fetch: fetchFn }),
    model: "gpt-4.1-mini",
    provider: "openai-fallback",
  };
}

/**
 * Get DeepSeek R1 (Reasoner) client for long-timeframe predictions (7D, 30D).
 * DeepSeek R1 excels at complex multi-step reasoning needed for longer forecasts.
 * 
 * Falls back through: DeepSeek R1 -> DeepSeek Chat -> OpenRouter -> OpenAI
 */
function getDeepSeekReasonerClient(): { client: OpenAI; model: string; provider: string } {
  // DeepSeek R1 is only available via direct DeepSeek API (not free on OpenRouter)
  const deepseekKey = process.env.DEEPSEEK_API_KEY;
  if (deepseekKey) {
    return {
      client: new OpenAI({ apiKey: deepseekKey, baseURL: "https://api.deepseek.com/v1", timeout: 30000, maxRetries: 1, fetch: globalThis.fetch }),
      model: "deepseek-reasoner", // DeepSeek R1 - advanced reasoning
      provider: "deepseek-r1",
    };
  }
  // Fall back to the standard chain (OpenRouter free DeepSeek -> OpenAI)
  return getDeepSeekClient();
}

/**
 * Rate-limit-aware AI completion wrapper.
 * Tries the primary provider first. If it returns 429 (rate limited) or 5xx,
 * automatically retries with the next provider in the fallback chain.
 * This distributes load across DeepSeek Direct → OpenRouter Free → OpenAI GPT-4.1-mini,
 * giving 3x the effective rate limit capacity.
 */
async function callAIWithFallback(params: {
  messages: Array<{ role: string; content: string }>;
  max_tokens: number;
  temperature: number;
  response_format?: { type: string };
  functionName: string;
}): Promise<{ content: string; model: string; provider: string; tokens: number }> {
  // Build ordered list of providers to try
  const providers: Array<{ client: OpenAI; model: string; provider: string }> = [];
  
  // Use native fetch for all OpenAI SDK clients — the SDK's built-in HTTP client
  // fails with "Connection error" on Cloud Run, but native fetch works fine.
  const fetchFn = globalThis.fetch;

  const deepseekKey = process.env.DEEPSEEK_API_KEY;
  if (deepseekKey) {
    providers.push({
      client: new OpenAI({ apiKey: deepseekKey, baseURL: "https://api.deepseek.com/v1", timeout: 30000, maxRetries: 1, fetch: fetchFn }),
      model: "deepseek-chat",
      provider: "deepseek",
    });
  }

  const openrouterKey = process.env.OPENROUTER_API_KEY;
  if (openrouterKey) {
    providers.push({
      client: new OpenAI({
        apiKey: openrouterKey,
        baseURL: "https://openrouter.ai/api/v1",
        timeout: 30000,
        maxRetries: 1,
        fetch: fetchFn,
        defaultHeaders: {
          "HTTP-Referer": "https://cryptosage.app",
          "X-Title": "CryptoSage",
        },
      }),
      model: "deepseek/deepseek-chat:free",
      provider: "openrouter-deepseek-free",
    });
  }

  const openaiKey = process.env.OPENAI_API_KEY;
  if (openaiKey) {
    providers.push({
      client: new OpenAI({ apiKey: openaiKey, timeout: 30000, maxRetries: 1, fetch: fetchFn }),
      model: "gpt-4.1-mini",
      provider: "openai-fallback",
    });
  }
  
  if (providers.length === 0) {
    throw new HttpsError("failed-precondition", "No AI API keys configured");
  }
  
  let lastError: unknown = null;
  const errors: string[] = [];

  for (let i = 0; i < providers.length; i++) {
    const { client, model, provider } = providers[i];
    try {
      const completionParams: Record<string, unknown> = {
        model,
        messages: params.messages,
        max_tokens: params.max_tokens,
        temperature: params.temperature,
      };
      if (params.response_format) {
        completionParams.response_format = params.response_format;
      }

      const completion = await client.chat.completions.create(completionParams as never);
      const content = (completion as { choices: Array<{ message: { content: string } }> }).choices[0]?.message?.content || "";
      const tokens = (completion as { usage?: { total_tokens?: number } }).usage?.total_tokens || 0;

      return { content, model, provider, tokens };
    } catch (err: unknown) {
      lastError = err;
      const status = (err as { status?: number }).status;
      const errMsg = (err as { message?: string }).message || String(err);
      const errCode = (err as { code?: string }).code;
      errors.push(`${provider}: ${status || errCode || "unknown"} - ${errMsg.substring(0, 100)}`);

      // Log detailed error for debugging
      console.warn(`[${params.functionName}] Provider ${provider} failed: status=${status}, code=${errCode}, message=${errMsg.substring(0, 200)}`);

      // Try next provider if available
      if (i < providers.length - 1) {
        continue;
      }

      // Last provider failed — throw with context
      console.error(`[${params.functionName}] All ${providers.length} AI providers failed:\n${errors.join("\n")}`);
      throw err;
    }
  }

  throw lastError || new HttpsError("internal", "All AI providers failed");
}

// ============================================================================
// COINGECKO API KEY ROTATION & QUOTA MANAGEMENT
// ============================================================================

/**
 * CoinGecko Demo API key rotation system.
 * 
 * Supports multiple demo keys to spread monthly quota across accounts.
 * Set these in Firebase environment config:
 *   - COINGECKO_DEMO_API_KEY   (primary key)
 *   - COINGECKO_DEMO_API_KEY_2 (backup key - optional)
 *   - COINGECKO_DEMO_API_KEY_3 (third key - optional)
 * 
 * To add a backup key:
 *   firebase functions:config:set coingecko.demo_api_key_2="CG-your-second-key"
 * 
 * Or set as environment variable in .env:
 *   COINGECKO_DEMO_API_KEY_2=CG-your-second-key
 * 
 * Keys are rotated round-robin per call. If a key gets 429 rate-limited,
 * it's temporarily disabled and the next key is tried.
 */
const coinGeckoKeys: string[] = [];
let coinGeckoKeyIndex = 0;
let coinGeckoKeyDisabledUntil: Record<number, number> = {};

// Initialize key pool from environment variables
function initCoinGeckoKeys(): void {
  if (coinGeckoKeys.length > 0) return; // Already initialized
  
  const key1 = process.env.COINGECKO_DEMO_API_KEY;
  const key2 = process.env.COINGECKO_DEMO_API_KEY_2;
  const key3 = process.env.COINGECKO_DEMO_API_KEY_3;
  
  if (key1) coinGeckoKeys.push(key1);
  if (key2) coinGeckoKeys.push(key2);
  if (key3) coinGeckoKeys.push(key3);
  
  if (coinGeckoKeys.length === 0) {
    console.log("[CoinGecko] WARNING: No API keys configured. Using unauthenticated requests (10 calls/min limit).");
  } else {
    console.log(`[CoinGecko] Initialized ${coinGeckoKeys.length} API key(s) for rotation.`);
  }
}

/**
 * Get the next available CoinGecko API key (round-robin with disabled-key skipping).
 * Returns null if all keys are disabled (quota exhausted).
 */
function getNextCoinGeckoKey(): string | null {
  initCoinGeckoKeys();
  if (coinGeckoKeys.length === 0) return null;
  
  const now = Date.now();
  
  // Try each key starting from current index
  for (let i = 0; i < coinGeckoKeys.length; i++) {
    const idx = (coinGeckoKeyIndex + i) % coinGeckoKeys.length;
    const disabledUntil = coinGeckoKeyDisabledUntil[idx] || 0;
    
    if (now >= disabledUntil) {
      // This key is available - advance the index for next call
      coinGeckoKeyIndex = (idx + 1) % coinGeckoKeys.length;
      return coinGeckoKeys[idx];
    }
  }
  
  // All keys disabled - find the one that expires soonest
  let soonestIdx = 0;
  let soonestTime = Infinity;
  for (let i = 0; i < coinGeckoKeys.length; i++) {
    const t = coinGeckoKeyDisabledUntil[i] || 0;
    if (t < soonestTime) { soonestTime = t; soonestIdx = i; }
  }
  
  console.log(`[CoinGecko] All keys disabled. Soonest available in ${Math.round((soonestTime - now) / 1000)}s. Using key ${soonestIdx} anyway.`);
  coinGeckoKeyIndex = (soonestIdx + 1) % coinGeckoKeys.length;
  return coinGeckoKeys[soonestIdx];
}

/**
 * Mark a CoinGecko key as rate-limited (disabled for a cooldown period).
 * Called when we receive a 429 response.
 */
function markCoinGeckoKeyRateLimited(key: string): void {
  const idx = coinGeckoKeys.indexOf(key);
  if (idx >= 0) {
    // Disable for 5 minutes (monthly quota) or 60 seconds (per-minute rate limit)
    // Use 5 minutes since monthly quota exhaustion is the more likely issue
    coinGeckoKeyDisabledUntil[idx] = Date.now() + 5 * 60 * 1000;
    console.log(`[CoinGecko] Key ${idx} rate-limited, disabled for 5 minutes. ${coinGeckoKeys.length - 1} other key(s) available.`);
  }
}

/**
 * Get CoinGecko API headers with the next available Demo API key.
 * Rotates between multiple keys to spread monthly quota.
 */
function getCoinGeckoHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    "Accept": "application/json",
    "User-Agent": "CryptoSage-Firebase/1.0",
  };
  const apiKey = getNextCoinGeckoKey();
  if (apiKey) {
    headers["x-cg-demo-api-key"] = apiKey;
  }
  return headers;
}

// ============================================================================
// COINGECKO USAGE TRACKING
// ============================================================================

/**
 * Track CoinGecko API calls in Firestore for quota monitoring.
 * Increments a daily counter so you can see exactly how many calls are being made.
 * Check Firestore > apiUsage > coingecko_month_YYYY-MM to see your monthly total.
 */
async function trackCoinGeckoCall(functionName: string, endpoint: string): Promise<void> {
  try {
    const now = new Date();
    const todayKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(now.getUTCDate()).padStart(2, "0")}`;
    const monthKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
    
    const dailyRef = db.collection("apiUsage").doc(`coingecko_${todayKey}`);
    const monthlyRef = db.collection("apiUsage").doc(`coingecko_month_${monthKey}`);
    
    // Increment daily counter
    await dailyRef.set({
      date: todayKey,
      totalCalls: admin.firestore.FieldValue.increment(1),
      [`calls_${functionName}`]: admin.firestore.FieldValue.increment(1),
      [`endpoint_${endpoint.replace(/[/.]/g, "_")}`]: admin.firestore.FieldValue.increment(1),
      lastCallAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    
    // Increment monthly counter
    await monthlyRef.set({
      month: monthKey,
      totalCalls: admin.firestore.FieldValue.increment(1),
      [`calls_${functionName}`]: admin.firestore.FieldValue.increment(1),
      lastCallAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (e) {
    // Don't fail the actual API call if tracking fails
    console.log("[trackCoinGeckoCall] Tracking failed (non-critical):", (e as Error).message);
  }
}

/**
 * Wrapper around fetch that tracks CoinGecko API calls AND handles key rotation on 429.
 * Use this instead of raw fetch() for ALL CoinGecko requests.
 * 
 * If the first key gets 429'd, it automatically retries with the next key.
 * If all keys are exhausted, returns the 429 response so callers can fall back to cache.
 */
async function fetchCoinGeckoTracked(
  url: string,
  functionName: string,
  endpoint: string
): Promise<Response> {
  await trackCoinGeckoCall(functionName, endpoint);
  
  // Get current headers (includes the next rotated key)
  const headers = getCoinGeckoHeaders();
  const currentKey = headers["x-cg-demo-api-key"] || "";
  
  const response = await fetch(url, { headers });
  
  // If rate-limited (429) or unauthorized (401), mark this key and try the next one.
  // 401 means the API key is invalid/expired — rotating to a backup key may resolve it.
  const shouldRetry = response.status === 429 || response.status === 401;
  
  if (shouldRetry && coinGeckoKeys.length > 1) {
    markCoinGeckoKeyRateLimited(currentKey);
    
    // Retry with next key
    const retryHeaders = getCoinGeckoHeaders();
    const retryKey = retryHeaders["x-cg-demo-api-key"] || "";
    
    // Only retry if we actually got a different key
    if (retryKey !== currentKey) {
      console.log(`[CoinGecko] Retrying ${endpoint} with backup key (HTTP ${response.status})...`);
      await trackCoinGeckoCall(functionName + "_retry", endpoint);
      return fetch(url, { headers: retryHeaders });
    }
  } else if (shouldRetry) {
    // Single key and rate-limited/unauthorized
    markCoinGeckoKeyRateLimited(currentKey);
    console.log(`[CoinGecko] HTTP ${response.status} on ${endpoint} (single key, no backup available)`);
  }
  
  return response;
}

/**
 * Check if cached data is still valid
 */
function isCacheValid(timestamp: admin.firestore.Timestamp | undefined, duration: number): boolean {
  if (!timestamp) return false;
  const now = Date.now();
  const cacheTime = timestamp.toMillis();
  return (now - cacheTime) < duration;
}

// SCALABILITY FIX: Request coalescing to prevent parallel API calls on cache miss
// When 100 users request the same data within milliseconds, only 1 request goes to the external API
const FETCH_LOCK_DURATION = 30000; // 30 seconds max lock duration

/**
 * Try to acquire a fetch lock for a cache key
 * Returns true if lock was acquired (this request should fetch)
 * Returns false if another request is already fetching (should wait)
 */
async function tryAcquireFetchLock(cacheKey: string): Promise<boolean> {
  const lockRef = db.collection("_fetchLocks").doc(cacheKey);
  
  try {
    const result = await db.runTransaction(async (transaction) => {
      const lockDoc = await transaction.get(lockRef);
      
      if (lockDoc.exists) {
        const data = lockDoc.data();
        const lockTime = data?.lockedAt?.toMillis() || 0;
        const now = Date.now();
        
        // If lock is still valid (not expired), another request is fetching
        if (now - lockTime < FETCH_LOCK_DURATION) {
          return false; // Don't acquire lock, wait instead
        }
        // Lock expired, we can take over
      }
      
      // Acquire the lock
      transaction.set(lockRef, {
        lockedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    
    return result;
  } catch (error) {
    // On error, allow the request to proceed (fail-open)
    console.error("Error acquiring fetch lock:", error);
    return true;
  }
}

/**
 * Release a fetch lock
 */
async function releaseFetchLock(cacheKey: string): Promise<void> {
  try {
    await db.collection("_fetchLocks").doc(cacheKey).delete();
  } catch (error) {
    console.error("Error releasing fetch lock:", error);
  }
}

/**
 * Wait for another request to complete the fetch, then return cached data
 * Polls the cache every 500ms until data is available or timeout
 */
async function waitForCachedData(
  cacheRef: admin.firestore.DocumentReference,
  cacheDuration: number,
  maxWaitMs: number = 10000
): Promise<{ data: admin.firestore.DocumentData | null; timedOut: boolean }> {
  const startTime = Date.now();
  const pollInterval = 500; // 500ms between polls
  
  while (Date.now() - startTime < maxWaitMs) {
    await new Promise(resolve => setTimeout(resolve, pollInterval));
    
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, cacheDuration)) {
        return { data, timedOut: false };
      }
    }
  }
  
  return { data: null, timedOut: true };
}

/**
 * Validate user authentication and return user ID
 */
async function validateAuth(request: { auth?: { uid: string } }): Promise<string | null> {
  return request.auth?.uid || null;
}

// ============================================================================
// GOOGLE TRENDS INTEGRATION
// ============================================================================

/**
 * Fetch Google Trends data for a specific coin
 * Used to gauge retail interest and potential price momentum
 * 
 * Returns:
 * - interestScore: 0-100 current search interest
 * - trend: "rising", "falling", or "stable"
 * - buyInterest: searches for "buy [coin]"
 * - sellInterest: searches for "[coin] crash/sell"
 * 
 * Cached for 1 hour per coin to avoid rate limiting
 */
async function fetchCoinGoogleTrends(symbol: string, coinName: string): Promise<{
  interestScore: number;
  trend: string;
  buyInterest: number;
  sellInterest: number;
  weekChange: number;
} | null> {
  const cacheKey = `googleTrends_${symbol.toLowerCase()}`;
  const cacheRef = db.collection("sharedAICache").doc(cacheKey);
  
  // Check cache first (1 hour cache per coin)
  try {
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, 60 * 60 * 1000)) { // 1 hour
        return {
          interestScore: data.interestScore,
          trend: data.trend,
          buyInterest: data.buyInterest,
          sellInterest: data.sellInterest,
          weekChange: data.weekChange,
        };
      }
    }
  } catch (e) {
    console.log(`[GoogleTrends] Cache check failed for ${symbol}`);
  }
  
  try {
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 7);
    
    // Normalize coin name for search
    const searchName = coinName.toLowerCase();
    
    // Main interest query (just the coin name)
    let interestScore = 0;
    let weekChange = 0;
    try {
      const result = await googleTrends.interestOverTime({
        keyword: searchName,
        startTime: startDate,
        endTime: endDate,
        geo: "",
      });
      const parsed = JSON.parse(result);
      const timeline = parsed?.default?.timelineData || [];
      if (timeline.length >= 2) {
        // Current interest (average of last 2 data points)
        const recentAvg = (timeline.slice(-2).reduce((s: number, t: { value: number[] }) => s + (t.value?.[0] || 0), 0)) / 2;
        // Week start interest (average of first 2 data points)
        const startAvg = (timeline.slice(0, 2).reduce((s: number, t: { value: number[] }) => s + (t.value?.[0] || 0), 0)) / 2;
        interestScore = Math.round(recentAvg);
        weekChange = startAvg > 0 ? Math.round(((recentAvg - startAvg) / startAvg) * 100) : 0;
      }
    } catch (e) {
      console.log(`[GoogleTrends] Failed to fetch "${searchName}":`, e);
    }
    
    await new Promise(resolve => setTimeout(resolve, 300));
    
    // Buy interest query
    let buyInterest = 0;
    try {
      const result = await googleTrends.interestOverTime({
        keyword: `buy ${searchName}`,
        startTime: startDate,
        endTime: endDate,
        geo: "",
      });
      const parsed = JSON.parse(result);
      const timeline = parsed?.default?.timelineData || [];
      if (timeline.length > 0) {
        buyInterest = Math.round(timeline.slice(-2).reduce((s: number, t: { value: number[] }) => s + (t.value?.[0] || 0), 0) / 2);
      }
    } catch (e) {
      // Smaller coins may not have "buy X" search data
    }
    
    await new Promise(resolve => setTimeout(resolve, 300));
    
    // Sell/crash interest query
    let sellInterest = 0;
    try {
      const result = await googleTrends.interestOverTime({
        keyword: `${searchName} crash`,
        startTime: startDate,
        endTime: endDate,
        geo: "",
      });
      const parsed = JSON.parse(result);
      const timeline = parsed?.default?.timelineData || [];
      if (timeline.length > 0) {
        sellInterest = Math.round(timeline.slice(-2).reduce((s: number, t: { value: number[] }) => s + (t.value?.[0] || 0), 0) / 2);
      }
    } catch (e) {
      // Smaller coins may not have "[X] crash" search data
    }
    
    // Determine trend
    let trend = "stable";
    if (weekChange > 20) trend = "rising";
    else if (weekChange < -20) trend = "falling";
    
    console.log(`[GoogleTrends] ${symbol}: interest=${interestScore}, trend=${trend}, weekChange=${weekChange}%, buy=${buyInterest}, sell=${sellInterest}`);
    
    // Cache the result
    await cacheRef.set({
      interestScore,
      trend,
      buyInterest,
      sellInterest,
      weekChange,
      symbol,
      coinName,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return { interestScore, trend, buyInterest, sellInterest, weekChange };
  } catch (error) {
    console.error(`[GoogleTrends] Failed to fetch trends for ${symbol}:`, error);
    return null;
  }
}

/**
 * Fetch Google Trends sentiment for crypto-related searches
 * Returns a sentiment score based on fear vs greed search patterns
 * 
 * Fear indicators: "bitcoin crash", "crypto crash", "sell bitcoin"
 * Greed indicators: "buy bitcoin", "bitcoin price prediction", "bitcoin all time high"
 * 
 * Cached for 30 minutes to avoid rate limiting
 */
async function fetchGoogleTrendsSentiment(): Promise<{ score: number; fearSearches: number; greedSearches: number } | null> {
  const cacheRef = db.collection("sharedAICache").doc("googleTrendsSentiment");
  
  // Check cache first (30 minute cache)
  try {
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, 30 * 60 * 1000)) {
        return {
          score: data.score,
          fearSearches: data.fearSearches,
          greedSearches: data.greedSearches,
        };
      }
    }
  } catch (e) {
    console.log("[GoogleTrends] Cache check failed, fetching fresh data");
  }
  
  try {
    // Fetch interest over time for fear and greed keywords
    // We compare the last 7 days of search interest
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 7);
    
    // Fear-related searches
    const fearKeywords = ["bitcoin crash", "crypto crash", "sell bitcoin"];
    // Greed-related searches  
    const greedKeywords = ["buy bitcoin", "bitcoin price prediction"];
    
    // Fetch fear searches
    let fearTotal = 0;
    let fearCount = 0;
    for (const keyword of fearKeywords) {
      try {
        const result = await googleTrends.interestOverTime({
          keyword,
          startTime: startDate,
          endTime: endDate,
          geo: "", // Worldwide
        });
        const parsed = JSON.parse(result);
        const timeline = parsed?.default?.timelineData || [];
        if (timeline.length > 0) {
          // Get average interest over the period
          const avg = timeline.reduce((sum: number, t: { value: number[] }) => sum + (t.value?.[0] || 0), 0) / timeline.length;
          fearTotal += avg;
          fearCount++;
        }
      } catch (e) {
        console.log(`[GoogleTrends] Failed to fetch "${keyword}":`, e);
      }
      // Small delay to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    
    // Fetch greed searches
    let greedTotal = 0;
    let greedCount = 0;
    for (const keyword of greedKeywords) {
      try {
        const result = await googleTrends.interestOverTime({
          keyword,
          startTime: startDate,
          endTime: endDate,
          geo: "", // Worldwide
        });
        const parsed = JSON.parse(result);
        const timeline = parsed?.default?.timelineData || [];
        if (timeline.length > 0) {
          const avg = timeline.reduce((sum: number, t: { value: number[] }) => sum + (t.value?.[0] || 0), 0) / timeline.length;
          greedTotal += avg;
          greedCount++;
        }
      } catch (e) {
        console.log(`[GoogleTrends] Failed to fetch "${keyword}":`, e);
      }
      await new Promise(resolve => setTimeout(resolve, 300));
    }
    
    // Calculate sentiment score
    // Higher fear searches relative to greed = lower score (more fear)
    // Higher greed searches relative to fear = higher score (more greed)
    const fearAvg = fearCount > 0 ? fearTotal / fearCount : 0;
    const greedAvg = greedCount > 0 ? greedTotal / greedCount : 0;
    
    if (fearAvg === 0 && greedAvg === 0) {
      console.log("[GoogleTrends] No valid search data retrieved");
      return null;
    }
    
    // Calculate ratio-based score
    // If greed >> fear, score is high (towards 100)
    // If fear >> greed, score is low (towards 0)
    const total = fearAvg + greedAvg;
    let score = 50; // Default neutral
    if (total > 0) {
      // greedRatio: 0 = all fear, 1 = all greed
      const greedRatio = greedAvg / total;
      // Map to 0-100 scale with some compression
      score = Math.round(20 + greedRatio * 60); // Range: 20-80
    }
    
    console.log(`[GoogleTrends] Sentiment: score=${score}, fear=${fearAvg.toFixed(1)}, greed=${greedAvg.toFixed(1)}`);
    
    // Cache the result
    await cacheRef.set({
      score,
      fearSearches: Math.round(fearAvg),
      greedSearches: Math.round(greedAvg),
      fearKeywords,
      greedKeywords,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return { score, fearSearches: Math.round(fearAvg), greedSearches: Math.round(greedAvg) };
  } catch (error) {
    console.error("[GoogleTrends] Failed to fetch trends:", error);
    return null;
  }
}

// ============================================================================
// AI INSIGHT FUNCTIONS
// ============================================================================

/**
 * Get market sentiment AI analysis
 * This is SHARED across all users - same response for everyone
 * 
 * Security: Rate limited, audit logged
 */
export const getMarketSentiment = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    const cacheRef = db.collection("sharedAICache").doc("marketSentiment");
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.marketSentiment)) {
        // Backward compatibility: generate summary from content if not present
        const summary = data.summary || (data.content ? data.content.split('.')[0] + '.' : "Market conditions evolving.");
        return {
          content: data.content,
          summary,
          score: data.score,
          verdict: data.verdict,
          confidence: data.confidence,
          keyFactors: data.keyFactors,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          model: data.model || "gpt-4o",
        };
      }
    }
    
    // Cache miss - call AI (DeepSeek preferred for crypto analysis, with fallback chain)
    const systemPrompt = `You are a professional cryptocurrency market analyst. Analyze the current market sentiment and provide:
1. A sentiment score from 0-100 (0=Extreme Fear, 50=Neutral, 100=Extreme Greed)
2. A verdict: "Extreme Fear", "Fear", "Neutral", "Greed", or "Extreme Greed"
3. A confidence level (0-100) based on how clear the signals are
4. 2-4 key factors driving the sentiment (short phrases, 2-4 words each)
5. A short summary (1 sentence, max 15 words) for mobile cards - focus on the key takeaway
6. A detailed analysis (2-3 sentences) explaining the market conditions

Consider: Bitcoin price action, altcoin performance, market volatility, trading volumes, and macro sentiment.

IMPORTANT: Respond ONLY with valid JSON in this exact format:
{
  "score": <number 0-100>,
  "verdict": "<string>",
  "confidence": <number 0-100>,
  "keyFactors": ["<factor1>", "<factor2>", ...],
  "summary": "<1 sentence, max 15 words>",
  "analysis": "<2-3 sentence detailed analysis>"
}`;

    const userPrompt = `Analyze the current cryptocurrency market sentiment. Today is ${new Date().toISOString().split('T')[0]}.
Provide your analysis as structured JSON only.`;

    let score = 50;
    let verdict = "Neutral";
    let confidence = 50;
    let keyFactors: string[] = [];
    let summary = "Market sentiment updating...";
    let content = "Market sentiment analysis unavailable.";
    let modelUsed = "fallback";
    let providerUsed = "none";
    let tokensUsed = 0;

    try {
      const aiResult = await callAIWithFallback({
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 400,
        temperature: 0.5,
        functionName: "getMarketSentiment",
      });
      modelUsed = aiResult.model;
      providerUsed = aiResult.provider;
      tokensUsed = aiResult.tokens;
      const rawContent = aiResult.content;

      try {
        // Extract JSON from response (handle markdown code blocks)
        let jsonStr = rawContent;
        const jsonMatch = rawContent.match(/```(?:json)?\s*([\s\S]*?)```/);
        if (jsonMatch) {
          jsonStr = jsonMatch[1].trim();
        } else if (rawContent.includes("{")) {
          jsonStr = rawContent.substring(rawContent.indexOf("{"));
          const lastBrace = jsonStr.lastIndexOf("}");
          if (lastBrace > 0) {
            jsonStr = jsonStr.substring(0, lastBrace + 1);
          }
        }

        const parsed = JSON.parse(jsonStr);
        score = Math.max(0, Math.min(100, Math.round(parsed.score || 50)));
        verdict = parsed.verdict || getVerdictFromScore(score);
        confidence = Math.max(0, Math.min(100, Math.round(parsed.confidence || 50)));
        keyFactors = Array.isArray(parsed.keyFactors) ? parsed.keyFactors.slice(0, 5) : [];
        summary = parsed.summary || (parsed.analysis ? parsed.analysis.split('.')[0] + '.' : "Market conditions evolving.");
        content = parsed.analysis || rawContent;
      } catch {
        // Fallback to raw content if JSON parsing fails
        content = rawContent;
        summary = rawContent.split('.')[0] + '.';
        verdict = getVerdictFromScore(score);
      }
    } catch (aiError) {
      // All AI providers failed — return stale cache if available, or static fallback
      console.error("[getMarketSentiment] All AI providers failed, using fallback:", aiError);

      // Try returning expired cache rather than crashing
      const staleCache = await cacheRef.get();
      if (staleCache.exists) {
        const data = staleCache.data();
        if (data) {
          const staleSummary = data.summary || (data.content ? data.content.split('.')[0] + '.' : "Market conditions evolving.");
          return {
            content: data.content || "Market sentiment analysis temporarily unavailable.",
            summary: staleSummary,
            score: data.score ?? 50,
            verdict: data.verdict || "Neutral",
            confidence: data.confidence ?? 30,
            keyFactors: data.keyFactors || [],
            cached: true,
            updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() || new Date().toISOString(),
            model: data.model || "stale-cache",
          };
        }
      }

      // No cache at all — return static default instead of INTERNAL error
      summary = "AI analysis temporarily unavailable.";
      content = "Market sentiment analysis is temporarily unavailable. All AI providers are currently unreachable. Please try again later.";
      keyFactors = ["AI providers unavailable"];
      modelUsed = "static-fallback";
    }

    // Cache the result (only if we got AI data, not static fallback)
    if (modelUsed !== "static-fallback") {
      await cacheRef.set({
        content,
        summary,
        score,
        verdict,
        confidence,
        keyFactors,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        model: modelUsed,
        provider: providerUsed,
        tokens: tokensUsed,
      });

      // Audit log for cache miss (costs money)
      await logAuditEvent("ai_cache_miss", request, { function: "getMarketSentiment", provider: providerUsed });
    }

    return {
      content,
      summary,
      score,
      verdict,
      confidence,
      keyFactors,
      cached: modelUsed === "static-fallback",
      updatedAt: new Date().toISOString(),
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getMarketSentiment");
  }
});

/**
 * Helper to derive verdict from score
 */
function getVerdictFromScore(score: number): string {
  if (score < 20) return "Extreme Fear";
  if (score < 40) return "Fear";
  if (score < 60) return "Neutral";
  if (score < 80) return "Greed";
  return "Extreme Greed";
}

// ============================================================================
// CRYPTOSAGE AI SENTIMENT - Real-time market sentiment calculation
// ============================================================================

/**
 * Helper functions for sentiment calculation
 */
function safeMedian(arr: number[]): number {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function stddev(arr: number[]): number {
  if (arr.length < 2) return 0;
  const mean = arr.reduce((a, b) => a + b, 0) / arr.length;
  const squaredDiffs = arr.map(x => Math.pow(x - mean, 2));
  return Math.sqrt(squaredDiffs.reduce((a, b) => a + b, 0) / (arr.length - 1));
}

function mad(arr: number[]): number {
  if (arr.length === 0) return 0;
  const median = safeMedian(arr);
  const deviations = arr.map(x => Math.abs(x - median));
  return safeMedian(deviations);
}

function clampPercent(x: number): number {
  if (!isFinite(x)) return 0;
  return Math.max(-100, Math.min(100, x));
}

/**
 * CryptoSage AI Sentiment - Real-time market sentiment calculation
 * 
 * This provides a consistent sentiment score across ALL users by calculating
 * it server-side from live market data. The algorithm considers:
 * - Market breadth (% of top coins with positive 24h change)
 * - BTC 24h/7d momentum
 * - Altcoin performance and dispersion
 * - Risk-on/risk-off indicators
 * 
 * Cache duration: 3 minutes for real-time feel while reducing API load
 */
export const getCryptoSageAISentiment = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    const cacheRef = db.collection("sharedAICache").doc("cryptoSageAISentiment");
    const historyRef = db.collection("sharedAICache").doc("cryptoSageAIHistory");
    
    // Helper to get historical values from history document
    const getHistoricalValues = async () => {
      const historyDoc = await historyRef.get();
      if (!historyDoc.exists) return { yesterday: null, lastWeek: null, lastMonth: null };
      
      const historyData = historyDoc.data() || {};
      const dailyScores: Record<string, { score: number; verdict: string }> = historyData.dailyScores || {};
      
      const now = new Date();
      const getHistoricalScore = (daysAgo: number): { score: number; verdict: string } | null => {
        const targetDate = new Date(now);
        targetDate.setUTCDate(targetDate.getUTCDate() - daysAgo);
        const targetKey = `${targetDate.getUTCFullYear()}-${String(targetDate.getUTCMonth() + 1).padStart(2, "0")}-${String(targetDate.getUTCDate()).padStart(2, "0")}`;
        return dailyScores[targetKey] || null;
      };
      
      return {
        yesterday: getHistoricalScore(1),
        lastWeek: getHistoricalScore(7),
        lastMonth: getHistoricalScore(30),
      };
    };
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.cryptoSageAISentiment)) {
        // Fetch historical values
        const historical = await getHistoricalValues();
        
        return {
          score: data.score,
          verdict: data.verdict,
          breadth: data.breadth,
          btc24h: data.btc24h,
          btc7d: data.btc7d,
          altMedian: data.altMedian,
          volatility: data.volatility,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          // Include historical values
          yesterday: historical.yesterday,
          lastWeek: historical.lastWeek,
          lastMonth: historical.lastMonth,
        };
      }
    }
    
    // Cache miss - try Firestore first (zero CoinGecko API calls)
    console.log("[getCryptoSageAISentiment] Cache miss, checking Firestore for market data...");
    
    let coinsResponse: Response | null = null;
    let globalResponse: Response | null = null;
    
    // RATE LIMIT FIX: Try Firestore before calling CoinGecko API
    const firestoreCG = await db.collection("marketData").doc("coingeckoMarkets").get();
    const firestoreGlobal = await db.collection("marketData").doc("globalStats").get();
    
    if (firestoreCG.exists) {
      const fsData = firestoreCG.data();
      const syncedAt = fsData?.updatedAt?.toDate?.() || new Date(fsData?.syncedAt || 0);
      const ageMs = Date.now() - syncedAt.getTime();
      
      if (ageMs < 10 * 60 * 1000 && Array.isArray(fsData?.coins) && fsData.coins.length > 0) {
        console.log(`[getCryptoSageAISentiment] Using Firestore data (${fsData.coins.length} coins, ${Math.round(ageMs / 1000)}s old)`);
        // Create a fake Response-like object to avoid changing downstream code
        coinsResponse = new Response(JSON.stringify(fsData.coins), { status: 200 });
        
        if (firestoreGlobal.exists) {
          const globalData = firestoreGlobal.data();
          globalResponse = new Response(JSON.stringify({
            data: {
              market_cap_percentage: { btc: globalData?.btcDominance ?? 50 },
            },
          }), { status: 200 });
        }
      }
    }
    
    // Fallback: Only call CoinGecko if Firestore data is unavailable or stale
    if (!coinsResponse) {
      console.log("[getCryptoSageAISentiment] Firestore miss, fetching from CoinGecko API...");
      
      const coinGeckoUrl = "https://api.coingecko.com/api/v3/coins/markets?" +
        "vs_currency=usd&order=market_cap_desc&per_page=100&page=1&sparkline=true&" +
        "price_change_percentage=1h,24h,7d";
      
      const globalUrl = "https://api.coingecko.com/api/v3/global";
      
      [coinsResponse, globalResponse] = await Promise.all([
        fetchCoinGeckoTracked(coinGeckoUrl, "getCryptoSageAISentiment", "coins_markets"),
        fetchCoinGeckoTracked(globalUrl, "getCryptoSageAISentiment", "global").catch(() => null),
      ]);
    }
    
    if (!coinsResponse || !coinsResponse.ok) {
      throw new HttpsError("unavailable", `CoinGecko API error: ${coinsResponse?.status || "no response"}`);
    }
    
    const coins: Array<{
      symbol: string;
      market_cap: number;
      market_cap_rank: number;
      total_volume?: number;
      price_change_percentage_1h_in_currency?: number;
      price_change_percentage_24h_in_currency?: number;
      price_change_percentage_7d_in_currency?: number;
      price_change_percentage_24h?: number;
      sparkline_in_7d?: { price: number[] };
      ath?: number;
      current_price?: number;
    }> = await coinsResponse.json();
    
    // Parse global data for BTC dominance
    let btcDominance = 50; // Default neutral
    if (globalResponse?.ok) {
      try {
        const globalData = await globalResponse.json();
        btcDominance = globalData?.data?.market_cap_percentage?.btc ?? 50;
      } catch { /* ignore */ }
    }
    
    if (!Array.isArray(coins) || coins.length < 10) {
      throw new HttpsError("unavailable", "Insufficient market data");
    }
    
    // Define stablecoins to exclude
    const stablecoins = new Set(["USDT", "USDC", "BUSD", "DAI", "FDUSD", "TUSD", "USDP", "GUSD", "FRAX", "LUSD", "PYUSD"]);
    
    // Filter and sort by market cap
    const effectiveCoins = coins
      .filter(c => c.market_cap > 0)
      .sort((a, b) => (a.market_cap_rank || 9999) - (b.market_cap_rank || 9999))
      .slice(0, 100);
    
    // =========================================================================
    // FACTOR 1: Market Breadth (% of coins with positive 24h change)
    // =========================================================================
    const coinsWithChange = effectiveCoins.filter(c => {
      const change = c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h;
      return change !== undefined && change !== null && isFinite(change);
    });
    
    const upCoins = coinsWithChange.filter(c => {
      const change = c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h ?? 0;
      return change > 0;
    });
    
    // Simple breadth
    const simpleBreadth = coinsWithChange.length > 0 
      ? upCoins.length / coinsWithChange.length 
      : 0.5;
    
    // Market-cap weighted breadth
    const totalCap = coinsWithChange.reduce((sum, c) => sum + (c.market_cap || 0), 0);
    const upCap = upCoins.reduce((sum, c) => sum + (c.market_cap || 0), 0);
    const weightedBreadth = totalCap > 0 ? upCap / totalCap : 0.5;
    
    // Combined breadth (60% weighted, 40% simple)
    const breadthCombined = 0.6 * weightedBreadth + 0.4 * simpleBreadth;
    
    // =========================================================================
    // FACTOR 2: BTC Momentum (1h, 24h, 7d)
    // =========================================================================
    const btcCoin = effectiveCoins.find(c => c.symbol.toUpperCase() === "BTC");
    const btc24h = btcCoin?.price_change_percentage_24h_in_currency ?? btcCoin?.price_change_percentage_24h ?? 0;
    const btc1h = btcCoin?.price_change_percentage_1h_in_currency ?? 0;
    
    // BTC 7d from sparkline or direct
    let btc7d = btcCoin?.price_change_percentage_7d_in_currency ?? 0;
    if (btc7d === 0 && btcCoin?.sparkline_in_7d?.price) {
      const prices = btcCoin.sparkline_in_7d.price;
      if (prices.length >= 2) {
        const startPrice = prices[0];
        const endPrice = prices[prices.length - 1];
        if (startPrice > 0 && endPrice > 0) {
          btc7d = ((endPrice - startPrice) / startPrice) * 100;
        }
      }
    }
    
    // =========================================================================
    // FACTOR 3: ETH as Leading Indicator
    // ETH often leads altcoin rallies/dumps - its relative strength matters
    // =========================================================================
    const ethCoin = effectiveCoins.find(c => c.symbol.toUpperCase() === "ETH");
    const eth24h = ethCoin?.price_change_percentage_24h_in_currency ?? ethCoin?.price_change_percentage_24h ?? 0;
    const ethVsBtc24h = eth24h - btc24h; // Positive = ETH outperforming = risk-on
    
    // =========================================================================
    // FACTOR 4: Altcoin Analysis
    // =========================================================================
    const altcoins = effectiveCoins.filter(c => 
      c.symbol.toUpperCase() !== "BTC" && !stablecoins.has(c.symbol.toUpperCase())
    );
    
    const altChanges = altcoins
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && c !== null && isFinite(c));
    
    const altMedian = safeMedian(altChanges);
    const dispersion = 0.5 * stddev(altChanges) + 0.5 * mad(altChanges);
    
    // =========================================================================
    // FACTOR 5: Risk Tilt (Small vs Large, Alts vs BTC)
    // =========================================================================
    const largeAlts = altcoins.slice(0, 50);
    const smallAlts = altcoins.slice(50, 100);
    
    const largeChanges = largeAlts
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && isFinite(c));
    const smallChanges = smallAlts
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && isFinite(c));
    
    const largeMedian = safeMedian(largeChanges);
    const smallMedian = safeMedian(smallChanges);
    const smallVsLargeDelta = smallMedian - largeMedian;
    const altsVsBTCDelta = altMedian - btc24h;
    
    // =========================================================================
    // FACTOR 6: BTC Dominance (Flight to Safety Indicator)
    // High BTC dominance (>55%) often indicates fear - money flowing to "safe" BTC
    // Low BTC dominance (<45%) indicates greed - money flowing to riskier alts
    // =========================================================================
    // Normalize around 50% dominance as neutral
    const btcDomTerm = (btcDominance - 50) / 10; // ~[-1, 1] for typical range 40-60%
    // Higher dominance = more fear = negative contribution
    const btcDomContrib = -btcDomTerm * 4.0;
    
    // =========================================================================
    // FACTOR 7: Momentum Consistency (Are timeframes aligned?)
    // When 1h, 24h, and 7d all agree, the signal is stronger
    // =========================================================================
    const btcMomentumAligned = (
      (btc1h > 0 && btc24h > 0 && btc7d > 0) || 
      (btc1h < 0 && btc24h < 0 && btc7d < 0)
    );
    const momentumBonus = btcMomentumAligned ? (btc24h > 0 ? 3.0 : -3.0) : 0;
    
    // =========================================================================
    // FACTOR 8: Volume Confirmation
    // High volume on up days = bullish confirmation
    // We use volume/market_cap ratio to normalize across coins
    // =========================================================================
    const volumeRatios = effectiveCoins
      .filter(c => c.total_volume && c.market_cap && c.market_cap > 0)
      .map(c => ({
        ratio: (c.total_volume || 0) / c.market_cap,
        change: c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h ?? 0
      }));
    
    // Calculate volume-weighted sentiment: high volume on up moves = bullish
    let volumeSentiment = 0;
    if (volumeRatios.length > 10) {
      const avgRatio = volumeRatios.reduce((s, v) => s + v.ratio, 0) / volumeRatios.length;
      const highVolumeCoins = volumeRatios.filter(v => v.ratio > avgRatio * 1.2);
      if (highVolumeCoins.length > 0) {
        const avgChange = highVolumeCoins.reduce((s, v) => s + v.change, 0) / highVolumeCoins.length;
        volumeSentiment = Math.tanh(avgChange / 5.0) * 3.0; // Capped contribution
      }
    }
    
    // =========================================================================
    // FACTOR 9: Distance from ATH (Market Euphoria/Depression)
    // Many coins near ATH = euphoria, many coins far from ATH = depression
    // =========================================================================
    const athDistances = effectiveCoins
      .filter(c => c.ath && c.current_price && c.ath > 0)
      .map(c => ((c.current_price || 0) / (c.ath || 1)) * 100); // % of ATH
    
    let athSentiment = 0;
    if (athDistances.length > 20) {
      const avgAthPct = athDistances.reduce((s, v) => s + v, 0) / athDistances.length;
      // 80%+ of ATH = euphoria, 30%- = depression
      athSentiment = Math.tanh((avgAthPct - 50) / 25) * 3.0;
    }
    
    // =========================================================================
    // FACTOR 10: Google Trends Sentiment (Social/Search Signal)
    // Measures retail fear vs greed through search behavior
    // "bitcoin crash" vs "buy bitcoin" searches
    // =========================================================================
    let googleTrendsSentiment = 0;
    try {
      const trendsData = await fetchGoogleTrendsSentiment();
      if (trendsData) {
        // trendsData.score is 20-80 range, normalize to contribution
        // Deviation from 50 (neutral) contributes to score
        googleTrendsSentiment = (trendsData.score - 50) / 10; // Range: -3 to +3
        console.log(`[getCryptoSageAISentiment] Google Trends: score=${trendsData.score}, contrib=${googleTrendsSentiment.toFixed(1)}`);
      }
    } catch (e) {
      console.log("[getCryptoSageAISentiment] Google Trends unavailable, skipping");
    }
    
    // =========================================================================
    // CALCULATE FINAL SCORE
    // =========================================================================
    const breadthTerm = (breadthCombined - 0.5) * 2.0; // [-1, 1]
    const disp = Math.max(0, Math.min(100, dispersion));
    
    // Volatility-adaptive weights
    const volFactor = Math.min(1.0, Math.tanh(disp / 20.0));
    const calmFactor = 1.0 - volFactor;
    
    // Base weights for each factor
    const wBreadth = 12.0;              // Market breadth (core factor)
    const wBTC24 = 10.0;                // BTC 24h momentum
    const wBTC7 = 6.0 + 2.0 * calmFactor;   // BTC 7d trend
    const wBTC1h = 1.0 + 1.5 * calmFactor;  // BTC 1h (small, for noise reduction)
    const wAltMed = 4.0 + 2.0 * calmFactor; // Altcoin median
    const wDispPenalty = 6.0 + 10.0 * volFactor;  // Volatility penalty
    const wRiskSmallVsLarge = 2.0 + 1.0 * calmFactor;
    const wRiskAltsVsBTC = 2.0 + 1.0 * calmFactor;
    const wEthVsBtc = 2.0 + 1.0 * calmFactor;  // ETH leading indicator
    
    // Calculate individual contributions
    const contribBTC24 = wBTC24 * Math.tanh(clampPercent(btc24h) / 8.0);
    const contribBreadth = wBreadth * breadthTerm;
    const contribBTC7 = wBTC7 * Math.tanh(clampPercent(btc7d) / 15.0);
    const contribBTC1h = wBTC1h * Math.tanh(clampPercent(btc1h) / 3.0);
    const contribAltMed = wAltMed * Math.tanh(clampPercent(altMedian) / 6.0);
    const contribDisp = -wDispPenalty * Math.tanh(disp / 15.0);
    const contribRiskSmall = wRiskSmallVsLarge * Math.tanh(smallVsLargeDelta / 3.0);
    const contribRiskAlts = wRiskAltsVsBTC * Math.tanh(altsVsBTCDelta / 4.0);
    const contribEthVsBtc = wEthVsBtc * Math.tanh(ethVsBtc24h / 4.0);
    
    let scoreRaw = 50.0
      + contribBTC24           // BTC daily momentum
      + contribBreadth         // Market breadth
      + contribBTC7            // BTC weekly trend
      + contribBTC1h           // BTC short-term
      + contribAltMed          // Altcoin performance
      + contribDisp            // Volatility penalty
      + contribRiskSmall       // Small vs large cap
      + contribRiskAlts        // Alts vs BTC
      + contribEthVsBtc        // ETH leading indicator
      + btcDomContrib          // BTC dominance (flight to safety)
      + momentumBonus          // Timeframe alignment bonus
      + volumeSentiment        // Volume confirmation
      + athSentiment           // Distance from ATH
      + googleTrendsSentiment; // Google Trends (retail search sentiment)
    
    // Apply guards to prevent extreme values in normal markets
    const coverageRatio = coinsWithChange.length / effectiveCoins.length;
    if (coverageRatio < 0.3) {
      // Low coverage - compress towards neutral
      scoreRaw = 50 + (scoreRaw - 50) * 0.5;
    }
    
    // Soft clamp: allow 5-95 range but compress extremes
    if (scoreRaw < 15) scoreRaw = 10 + (scoreRaw - 10) * 0.5;
    if (scoreRaw > 85) scoreRaw = 90 - (90 - scoreRaw) * 0.5;
    
    const score = Math.round(Math.max(0, Math.min(100, scoreRaw)));
    const verdict = getVerdictFromScore(score);
    
    // Detailed logging for debugging
    console.log(`[getCryptoSageAISentiment] Score: ${score} (${verdict})`);
    console.log(`  Breadth: ${(breadthCombined * 100).toFixed(0)}% (contrib: ${contribBreadth.toFixed(1)})`);
    console.log(`  BTC: 1h=${btc1h.toFixed(1)}%, 24h=${btc24h.toFixed(1)}%, 7d=${btc7d.toFixed(1)}%`);
    console.log(`  ETH vs BTC: ${ethVsBtc24h.toFixed(1)}% (contrib: ${contribEthVsBtc.toFixed(1)})`);
    console.log(`  BTC Dom: ${btcDominance.toFixed(1)}% (contrib: ${btcDomContrib.toFixed(1)})`);
    console.log(`  Volatility: ${disp.toFixed(1)} (penalty: ${contribDisp.toFixed(1)})`);
    console.log(`  Momentum aligned: ${btcMomentumAligned} (bonus: ${momentumBonus.toFixed(1)})`);
    console.log(`  Google Trends: ${googleTrendsSentiment.toFixed(1)}`);
    console.log(`  Volume sentiment: ${volumeSentiment.toFixed(1)}, ATH sentiment: ${athSentiment.toFixed(1)}`);
    
    console.log(`[getCryptoSageAISentiment] Score: ${score} (${verdict}), ` +
      `breadth=${(breadthCombined * 100).toFixed(0)}%, ` +
      `BTC24h=${btc24h.toFixed(1)}%, BTC7d=${btc7d.toFixed(1)}%, ` +
      `altMed=${altMedian.toFixed(1)}%, disp=${disp.toFixed(1)}`);
    
    // Store daily historical snapshot (once per UTC day)
    const now = new Date();
    const todayKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(now.getUTCDate()).padStart(2, "0")}`;
    // historyRef is already defined at the top of this function
    
    // Get existing history
    const historyDoc = await historyRef.get();
    const historyData = historyDoc.exists ? historyDoc.data() || {} : {};
    const dailyScores: Record<string, { score: number; verdict: string; timestamp: string }> = historyData.dailyScores || {};
    
    // Store today's score if not already stored
    if (!dailyScores[todayKey]) {
      dailyScores[todayKey] = {
        score,
        verdict,
        timestamp: now.toISOString(),
      };
      
      // Keep only last 35 days of history
      const sortedKeys = Object.keys(dailyScores).sort().reverse();
      const keysToKeep = sortedKeys.slice(0, 35);
      const trimmedScores: typeof dailyScores = {};
      for (const key of keysToKeep) {
        trimmedScores[key] = dailyScores[key];
      }
      
      await historyRef.set({
        dailyScores: trimmedScores,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      console.log(`[getCryptoSageAISentiment] Stored daily history for ${todayKey}: score=${score}`);
    }
    
    // Retrieve historical values (yesterday, last week, last month)
    const getHistoricalScore = (daysAgo: number): { score: number; verdict: string } | null => {
      const targetDate = new Date(now);
      targetDate.setUTCDate(targetDate.getUTCDate() - daysAgo);
      const targetKey = `${targetDate.getUTCFullYear()}-${String(targetDate.getUTCMonth() + 1).padStart(2, "0")}-${String(targetDate.getUTCDate()).padStart(2, "0")}`;
      return dailyScores[targetKey] || null;
    };
    
    const yesterday = getHistoricalScore(1);
    const lastWeek = getHistoricalScore(7);
    const lastMonth = getHistoricalScore(30);
    
    // Cache the result
    await cacheRef.set({
      score,
      verdict,
      breadth: Math.round(breadthCombined * 100),
      btc24h: Math.round(btc24h * 100) / 100,
      btc7d: Math.round(btc7d * 100) / 100,
      altMedian: Math.round(altMedian * 100) / 100,
      volatility: Math.round(disp * 10) / 10,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return {
      score,
      verdict,
      breadth: Math.round(breadthCombined * 100),
      btc24h: Math.round(btc24h * 100) / 100,
      btc7d: Math.round(btc7d * 100) / 100,
      altMedian: Math.round(altMedian * 100) / 100,
      volatility: Math.round(disp * 10) / 10,
      cached: false,
      updatedAt: new Date().toISOString(),
      // Historical values (null if not yet available)
      yesterday: yesterday ? { score: yesterday.score, verdict: yesterday.verdict } : null,
      lastWeek: lastWeek ? { score: lastWeek.score, verdict: lastWeek.verdict } : null,
      lastMonth: lastMonth ? { score: lastMonth.score, verdict: lastMonth.verdict } : null,
    };
  } catch (error) {
    console.error("[getCryptoSageAISentiment] Error:", error);
    throw safeError(error, "getCryptoSageAISentiment");
  }
});

/**
 * Get AI insight for a specific coin
 * This is SHARED across all users for the same coin
 * 
 * Security: Input validation, rate limiting, audit logged
 */
export const getCoinInsight = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const coinId = validateCoinId(request.data?.coinId);
    const symbol = validateCoinSymbol(request.data?.symbol);
    const coinName = sanitizeString(request.data?.coinName, 100) || symbol;
    const price = validateNumber(request.data?.price, 0, 1e15);
    const change24h = validateNumber(request.data?.change24h, -100, 10000, 0);
    const change7d = validateNumber(request.data?.change7d, -100, 10000, 0);
    const marketCap = validateNumber(request.data?.marketCap, 0, 1e18);
    const volume24h = validateNumber(request.data?.volume24h, 0, 1e18);
    
    const cacheRef = db.collection("sharedAICache").doc(`coin_${coinId}`);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.coinInsight)) {
        return {
          content: data.content,
          technicalSummary: data.technicalSummary,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          model: data.model || "gpt-4o",
        };
      }
    }
    
    // Cache miss - call AI (DeepSeek preferred for crypto analysis, with fallback chain)
    // Fetch Google Trends data for retail interest signal
    let trendsContext = "";
    try {
      const trendsData = await fetchCoinGoogleTrends(symbol, coinName);
      if (trendsData && trendsData.interestScore > 0) {
        trendsContext = `
- Google Search Interest: ${trendsData.interestScore}/100 (${trendsData.trend}, ${trendsData.weekChange > 0 ? "+" : ""}${trendsData.weekChange}% week)`;
        if (trendsData.buyInterest > 20 || trendsData.sellInterest > 20) {
          trendsContext += `
- Retail Sentiment: ${trendsData.buyInterest > trendsData.sellInterest ? "Buying interest rising" : trendsData.sellInterest > trendsData.buyInterest ? "Concern/fear rising" : "Mixed"}`;
        }
      }
    } catch (e) {
      // Non-critical
    }
    
    // Detect asset type from coinId prefix for tailored prompts
    const isCommodity = coinId.startsWith("commodity-");
    const isStock = coinId.startsWith("stock-");
    
    const systemPrompt = isCommodity
      ? `You are a commodities market analyst providing brief commodity insights.
Be concise (3-4 sentences), factual, and avoid price predictions.
Focus on: recent price action, supply/demand factors, geopolitical influences, seasonal trends, and what commodity traders should watch.
Reference relevant macro factors like USD strength, inflation data, or central bank policy when applicable.`
      : isStock
      ? `You are an equity analyst providing brief stock insights.
Be concise (3-4 sentences), factual, and avoid price predictions.
Focus on: recent performance, sector trends, earnings context, institutional sentiment, and key catalysts.`
      : `You are a cryptocurrency analyst providing brief coin insights. 
Be concise (3-4 sentences), factual, and avoid price predictions. 
Focus on: recent performance context, key metrics, retail interest trends, and what makes this coin notable.
If Google Trends data shows rising interest, mention it as a factor traders should consider.`;

    const assetLabel = isCommodity ? "commodity" : isStock ? "stock" : "coin";
    
    const userPrompt = isCommodity
      ? `Provide a brief analysis for ${coinName} (${symbol}):
- Current Price: $${price.toLocaleString()}
- 24h Change: ${change24h.toFixed(2)}%${trendsContext}

Give a 3-4 sentence insight about this commodity's current state and what traders should know.`
      : `Provide a brief analysis for ${coinName} (${symbol}):
- Current Price: $${price.toLocaleString()}
- 24h Change: ${change24h.toFixed(2)}%
- 7d Change: ${change7d.toFixed(2)}%
- Market Cap: $${marketCap.toLocaleString()}
- 24h Volume: $${volume24h.toLocaleString()}${trendsContext}

Give a 3-4 sentence insight about this ${assetLabel}'s current state and what traders should know.`;

    const aiResult = await callAIWithFallback({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 300,
      temperature: 0.7,
      functionName: "getCoinInsight",
    });
    const modelUsed = aiResult.model;
    const content = aiResult.content || "Unable to generate coin insight.";
    
    // Cache the result
    await cacheRef.set({
      content,
      technicalSummary: null,
      coinId,
      symbol,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: modelUsed,
      provider: aiResult.provider,
      tokens: aiResult.tokens,
    });
    
    // Audit log for cache miss
    await logAuditEvent("ai_cache_miss", request, { function: "getCoinInsight", coinId, provider: aiResult.provider });
    
    return {
      content,
      technicalSummary: null,
      cached: false,
      updatedAt: new Date().toISOString(),
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getCoinInsight");
  }
});

/**
 * Get AI explanation for why a coin is moving ("Why is it moving?" feature)
 * This is SHARED across all users for the same coin
 * First user triggers AI generation, subsequent users get cached result
 * 
 * Cache key: priceMovement_{symbol}_{hourBucket}
 * This ensures explanations are regenerated every 2 hours but shared within that window
 * 
 * Security: Input validation, rate limiting, audit logged
 */
export const getPriceMovementExplanation = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const symbol = validateCoinSymbol(request.data?.symbol);
    const coinName = sanitizeString(request.data?.coinName, 100) || symbol;
    const currentPrice = validateNumber(request.data?.currentPrice, 0, 1e15);
    const change24h = validateNumber(request.data?.change24h, -100, 10000, 0);
    const change7d = validateNumber(request.data?.change7d, -100, 10000, 0);
    const volume24h = validateNumber(request.data?.volume24h, 0, 1e18);
    
    // CRITICAL: Reject requests with $0 price — this means the client hasn't loaded
    // market data yet. If we generate an explanation with $0 data it gets cached for
    // 2 hours and ALL users see a nonsensical "no price change at $0" response.
    if (currentPrice <= 0) {
      throw new HttpsError("failed-precondition",
        "Invalid price data (price=$0). Market data may still be loading on the client.");
    }
    
    // Optional market context
    const btcChange24h = request.data?.btcChange24h as number | undefined;
    const ethChange24h = request.data?.ethChange24h as number | undefined;
    const fearGreedIndex = request.data?.fearGreedIndex as number | undefined;
    const smartMoneyScore = request.data?.smartMoneyScore as number | undefined;
    const exchangeFlowSentiment = request.data?.exchangeFlowSentiment as string | undefined;
    const marketRegime = request.data?.marketRegime as string | undefined;
    
    // Create cache key with 2-hour bucket for freshness
    // This ensures all users in the same 2-hour window get the same explanation
    const hourBucket = Math.floor(Date.now() / (2 * 60 * 60 * 1000));
    const cacheKey = `priceMovement_${symbol.toUpperCase()}_${hourBucket}`;
    const cacheRef = db.collection("sharedAICache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.priceMovementExplanation)) {
        return {
          summary: data.summary,
          reasons: data.reasons,
          btcChange24h: data.btcChange24h,
          ethChange24h: data.ethChange24h,
          fearGreedIndex: data.fearGreedIndex,
          isMarketWideMove: data.isMarketWideMove,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          model: data.model || "gpt-4o",
        };
      }
    }
    
    // Cache miss - generate explanation using AI (DeepSeek preferred, with fallback chain)
    
    // Determine if this is a market-wide move
    const isMarketWideMove = btcChange24h !== undefined && Math.abs(btcChange24h) > 3;
    
    // Build context for AI
    let marketContext = "";
    if (btcChange24h !== undefined) marketContext += `\nBTC 24H Change: ${btcChange24h.toFixed(2)}%`;
    if (ethChange24h !== undefined) marketContext += `\nETH 24H Change: ${ethChange24h.toFixed(2)}%`;
    if (fearGreedIndex !== undefined) marketContext += `\nFear & Greed Index: ${fearGreedIndex}/100`;
    if (smartMoneyScore !== undefined) marketContext += `\nSmart Money Index: ${smartMoneyScore}/100`;
    if (exchangeFlowSentiment) marketContext += `\nExchange Flow: ${exchangeFlowSentiment}`;
    if (marketRegime) marketContext += `\nMarket Regime: ${marketRegime}`;
    if (isMarketWideMove) marketContext += `\n⚠️ This appears to be part of a broader market movement`;
    
    // Fetch Google Trends for retail interest signal
    let trendsContext = "";
    try {
      const trendsData = await fetchCoinGoogleTrends(symbol, coinName);
      if (trendsData) {
        trendsContext = `\n\n=== RETAIL INTEREST (Google Trends) ===`;
        trendsContext += `\nSearch Interest: ${trendsData.interestScore}/100 (${trendsData.trend})`;
        trendsContext += `\nWeek-over-week Change: ${trendsData.weekChange > 0 ? "+" : ""}${trendsData.weekChange}%`;
        if (trendsData.buyInterest > 10) trendsContext += `\n"Buy ${coinName}" searches: ${trendsData.buyInterest} (${trendsData.buyInterest > 30 ? "HIGH - retail FOMO" : "moderate"})`;
        if (trendsData.sellInterest > 10) trendsContext += `\n"${coinName} crash" searches: ${trendsData.sellInterest} (${trendsData.sellInterest > 30 ? "HIGH - retail fear" : "moderate"})`;
        
        // Add interpretation hint
        if (trendsData.weekChange > 50) {
          trendsContext += `\n📈 SIGNIFICANT: Search interest SPIKED this week - likely viral/news driven`;
        } else if (trendsData.weekChange < -30) {
          trendsContext += `\n📉 Search interest dropped significantly - retail attention fading`;
        }
      }
    } catch (e) {
      // Non-critical
    }
    
    const systemPrompt = `You are a professional crypto market analyst explaining price movements.

Your analysis methodology:
1. WHALE/SMART MONEY DATA (Priority if significant activity detected):
   - Exchange inflows suggest selling pressure (bearish)
   - Exchange outflows suggest accumulation (bullish)
   - Smart Money Index > 55 = institutions buying, < 45 = institutions selling

2. MARKET REGIME CONTEXT:
   - In trending markets, movements often extend further
   - In ranging markets, look for mean reversion
   - High volatility regimes require wider context

3. CORRELATION CHECK:
   - If BTC/ETH moving similarly, it's likely market-wide
   - If coin moving independently, look for coin-specific factors

4. RETAIL INTEREST (Google Trends data if available):
   - Spiking search interest often accompanies or precedes big moves
   - High "buy X" searches = retail FOMO (often late to the move)
   - High "X crash" searches = retail fear (potential contrarian signal)
   - Use "retail" category when search trends are a significant factor

Be concise and factual. Respond ONLY with valid JSON.`;

    const userPrompt = `Explain why ${coinName} (${symbol}) has moved ${change24h.toFixed(2)}% in the last 24 hours.

=== PRICE DATA ===
Current Price: $${currentPrice.toLocaleString()}
24H Change: ${change24h.toFixed(2)}%
7D Change: ${change7d.toFixed(2)}%
24H Volume: $${volume24h.toLocaleString()}
${marketContext}${trendsContext}

=== INSTRUCTIONS ===
Provide a brief 1-2 sentence summary and list 2-4 possible reasons for the movement.

For each reason, categorize it as: news, whale, technical, sentiment, market, regulatory, exchange, retail, or other.
(Use "retail" category if Google Trends shows significant search interest changes)
Also rate confidence (high/medium/low) and impact (positive/negative/neutral).

Respond with ONLY valid JSON in this exact format:
{
  "summary": "Brief 1-2 sentence explanation",
  "reasons": [
    {
      "category": "market",
      "title": "Short reason title",
      "description": "Detailed explanation",
      "confidence": "medium",
      "impact": "positive"
    }
  ]
}`;

    const aiResult = await callAIWithFallback({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 512,
      temperature: 0.3,
      response_format: { type: "json_object" },
      functionName: "getPriceMovementExplanation",
    });
    const modelUsed = aiResult.model;
    const responseText = aiResult.content || "{}";
    
    // Parse the AI response
    let parsedResponse: { summary: string; reasons: Array<{
      category: string;
      title: string;
      description: string;
      confidence: string;
      impact: string;
    }> };
    
    try {
      parsedResponse = JSON.parse(responseText);
    } catch {
      // Fallback if JSON parsing fails
      parsedResponse = {
        summary: "Price movement analysis based on current market data.",
        reasons: [{
          category: "market",
          title: "Market Conditions",
          description: "Price is responding to current market conditions.",
          confidence: "medium",
          impact: change24h > 0 ? "positive" : "negative",
        }],
      };
    }
    
    // Cache the result
    await cacheRef.set({
      summary: parsedResponse.summary,
      reasons: parsedResponse.reasons,
      symbol: symbol.toUpperCase(),
      coinName,
      btcChange24h,
      ethChange24h,
      fearGreedIndex,
      isMarketWideMove,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: modelUsed,
      provider: aiResult.provider,
      tokens: aiResult.tokens,
    });
    
    // Audit log for cache miss
    await logAuditEvent("ai_cache_miss", request, { function: "getPriceMovementExplanation", symbol, provider: aiResult.provider });
    
    return {
      summary: parsedResponse.summary,
      reasons: parsedResponse.reasons,
      btcChange24h,
      ethChange24h,
      fearGreedIndex,
      isMarketWideMove,
      cached: false,
      updatedAt: new Date().toISOString(),
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getPriceMovementExplanation");
  }
});

// ============================================================================
// TECHNICAL ANALYSIS FUNCTIONS
// ============================================================================

/**
 * Get technical analysis summary for a coin
 * This is SHARED across all users for the same symbol/interval
 * Provides consistent pre-computed indicators across all app instances
 * 
 * Security: Rate limited, input validated
 */
export const getTechnicalsSummary = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting (use publicAI tier since this is shared data)
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const symbol = validateCoinSymbol(request.data?.symbol);
    const interval = sanitizeString(request.data?.interval || "1d", 10);
    
    // Validate interval
    const validIntervals = ["1m", "5m", "15m", "30m", "1h", "4h", "1d", "1D", "1w", "1W", "1M"];
    if (!validIntervals.includes(interval)) {
      throw new HttpsError("invalid-argument", "Invalid interval");
    }
    
    const cacheKey = `technicals_${symbol.toUpperCase()}_${interval}`;
    const cacheRef = db.collection("sharedAICache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.technicalSummary)) {
        return {
          ...data.summary,
          symbol: symbol.toUpperCase(),
          interval,
          source: "CryptoSage (Firebase)",
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // Cache miss - check if another request is already fetching
    const lockKey = `technicals_${symbol.toUpperCase()}_${interval}`;
    const gotLock = await tryAcquireFetchLock(lockKey);
    
    if (!gotLock) {
      // Wait for the other request to complete
      const waitResult = await waitForCachedData(
        cacheRef,
        CACHE_DURATIONS.technicalSummary,
        10000
      );
      
      if (waitResult.data) {
        return {
          ...waitResult.data.summary,
          symbol: symbol.toUpperCase(),
          interval,
          source: "CryptoSage (Firebase)",
          cached: true,
          updatedAt: waitResult.data.updatedAt.toDate().toISOString(),
        };
      }
      
      // Timed out waiting, proceed with our own fetch
    }
    
    try {
      // Fetch candles from Binance
      const candles = await fetchBinanceCandles(symbol, interval, 500);
      
      if (candles.length < 26) {
        throw new HttpsError("failed-precondition", "Insufficient data for technical analysis");
      }
      
      // Compute technical summary
      const currentPrice = candles[candles.length - 1].close;
      const summary = computeTechnicalsSummary(candles, currentPrice);
      
      // Store in cache
      await cacheRef.set({
        summary,
        symbol: symbol.toUpperCase(),
        interval,
        candleCount: candles.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        ...summary,
        symbol: symbol.toUpperCase(),
        interval,
        source: "CryptoSage (Firebase)",
        cached: false,
        updatedAt: summary.updatedAt,
      };
      
    } finally {
      // Release the fetch lock
      await releaseFetchLock(lockKey);
    }
    
  } catch (error) {
    throw safeError(error, "getTechnicalsSummary");
  }
});

/**
 * Get AI price prediction for a coin
 * This is SHARED across all users for the same coin/timeframe
 * 
 * Security: Rate limited, input validated, audit logged
 */
export const getPricePrediction = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "prediction");
    
    // Input validation
    const coinId = validateCoinId(request.data?.coinId);
    const symbol = validateCoinSymbol(request.data?.symbol);
    const timeframe = validateTimeframe(request.data?.timeframe);
    const currentPrice = request.data?.currentPrice ? validateNumber(request.data.currentPrice, 0, 10000000) : undefined;
    const fearGreedIndex = request.data?.fearGreedIndex ? validateNumber(request.data.fearGreedIndex, 0, 100) : undefined;
    const technicalIndicators = request.data?.technicalIndicators; // Optional
    
    const cacheKey = `prediction_${coinId}_${timeframe}`;
    const cacheRef = db.collection("sharedAICache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.prediction)) {
        // Validate cached priceRange - reject cache if it has bad data (0/0 range)
        const cachedRange = data.priceRange;
        const cacheHasBadRange = !cachedRange || 
          (cachedRange.low === 0 && cachedRange.high === 0) ||
          (cachedRange.low === undefined && cachedRange.high === undefined);
        
        if (cacheHasBadRange) {
          console.log(`[getPricePrediction] ⚠️ Rejecting cached prediction with bad priceRange for ${coinId} (${timeframe})`);
          // Fall through to fetch fresh prediction
        } else {
          return {
            prediction: data.prediction,
            confidence: data.confidence,
            priceRange: data.priceRange,
            reasoning: data.reasoning,
            cached: true,
            updatedAt: data.updatedAt.toDate().toISOString(),
            model: data.model || "gpt-4o",
          };
        }
      }
    }
    
    // Cache miss - call DeepSeek (Alpha Arena winner: +116% crypto return)
    // Use dual-model strategy: DeepSeek R1 for long timeframes (7d, 30d) for deeper reasoning,
    // DeepSeek V3.2 for short timeframes (1h, 4h, 12h, 24h) for faster, momentum-focused analysis.
    // Falls back to OpenAI gpt-4o if DEEPSEEK_API_KEY is not configured.
    const isLongTimeframe = ["7d", "30d", "90d", "1y"].includes(timeframe);
    const { client: aiClient, model: modelUsed, provider: aiProvider } = isLongTimeframe
      ? getDeepSeekReasonerClient()
      : getDeepSeekClient();
    
    // Audit log for cache miss (costs money)
    await logAuditEvent("ai_cache_miss", request, { function: "getPricePrediction", coinId, timeframe, model: modelUsed, provider: aiProvider });
    
    // Fetch global accuracy metrics to inform the AI
    let accuracyContext = "";
    try {
      const metricsDoc = await db.collection("globalAccuracyMetrics").doc("current").get();
      if (metricsDoc.exists) {
        const metrics = metricsDoc.data()!;
        const totalPredictions = metrics.totalPredictions || 0;
        
        if (totalPredictions >= 50) {
          // Only include if we have meaningful data
          const overallAccuracy = (metrics.directionAccuracyPercent || 50).toFixed(1);
          const timeframeAccuracy = metrics.timeframeAccuracy?.[timeframe]?.toFixed(1) || "N/A";
          const bullishAccuracy = metrics.directionBreakdown?.bullish?.toFixed(1) || "N/A";
          const bearishAccuracy = metrics.directionBreakdown?.bearish?.toFixed(1) || "N/A";
          const neutralAccuracy = metrics.directionBreakdown?.neutral?.toFixed(1) || "N/A";
          
          accuracyContext = `
HISTORICAL ACCURACY DATA (from ${totalPredictions.toLocaleString()} evaluated predictions):
- Overall direction accuracy: ${overallAccuracy}%
- ${timeframe.toUpperCase()} timeframe accuracy: ${timeframeAccuracy}%
- Bullish predictions accuracy: ${bullishAccuracy}%
- Bearish predictions accuracy: ${bearishAccuracy}%
- Neutral predictions accuracy: ${neutralAccuracy}%

Use this data to calibrate confidence. If ${timeframe} predictions historically underperform, be more conservative.
If bullish/bearish predictions historically fail more, consider leaning neutral when signals are weak.
`;
        }
      }
    } catch (error) {
      // Non-critical - continue without accuracy context
      console.log("Could not fetch accuracy metrics:", error);
    }
    
    // Build rich technical context from client-provided indicators
    let technicalContext = "";
    if (technicalIndicators) {
      const parts: string[] = ["Technical Indicators:"];
      if (technicalIndicators.rsi != null) parts.push(`- RSI(14): ${sanitizeString(String(technicalIndicators.rsi), 30)}`);
      if (technicalIndicators.stochRSI) parts.push(`- Stoch RSI: ${sanitizeString(String(technicalIndicators.stochRSI), 50)}`);
      if (technicalIndicators.macdSignal) parts.push(`- MACD Signal: ${sanitizeString(String(technicalIndicators.macdSignal), 30)}`);
      if (technicalIndicators.maTrend) parts.push(`- MA Structure: ${sanitizeString(String(technicalIndicators.maTrend), 40)}`);
      if (technicalIndicators.adx != null) parts.push(`- ADX(14): ${sanitizeString(String(technicalIndicators.adx), 30)}`);
      if (technicalIndicators.bollingerPosition) parts.push(`- Bollinger Bands: ${sanitizeString(String(technicalIndicators.bollingerPosition), 50)}`);
      if (technicalIndicators.volumeTrend) parts.push(`- Volume Trend: ${sanitizeString(String(technicalIndicators.volumeTrend), 30)}`);
      if (technicalIndicators.change24h != null) parts.push(`- 24H Change: ${sanitizeString(String(technicalIndicators.change24h), 20)}%`);
      if (technicalIndicators.change7d != null) parts.push(`- 7D Change: ${sanitizeString(String(technicalIndicators.change7d), 20)}%`);
      if (technicalIndicators.smartMoneyIndex != null) parts.push(`- Smart Money Index: ${sanitizeString(String(technicalIndicators.smartMoneyIndex), 30)}`);
      if (technicalIndicators.exchangeFlowSentiment) parts.push(`- Exchange Flow: ${sanitizeString(String(technicalIndicators.exchangeFlowSentiment), 40)}`);
      if (technicalIndicators.fundingRate != null) parts.push(`- Funding Rate: ${sanitizeString(String(technicalIndicators.fundingRate), 20)}`);
      if (technicalIndicators.btcDominance != null) parts.push(`- BTC Dominance: ${sanitizeString(String(technicalIndicators.btcDominance), 20)}%`);
      if (technicalIndicators.marketRegime) parts.push(`- Market Regime: ${sanitizeString(String(technicalIndicators.marketRegime), 30)}`);
      technicalContext = parts.length > 1 ? parts.join("\n") : "";
    }
    
    // Fetch Google Trends data for this coin (retail interest signal)
    let googleTrendsContext = "";
    try {
      // Map common symbols to full names for better Google Trends results
      const coinNameMap: Record<string, string> = {
        "BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "XRP": "XRP",
        "ADA": "Cardano", "DOGE": "Dogecoin", "DOT": "Polkadot", "AVAX": "Avalanche",
        "MATIC": "Polygon", "LINK": "Chainlink", "SHIB": "Shiba Inu", "LTC": "Litecoin",
        "UNI": "Uniswap", "ATOM": "Cosmos", "XLM": "Stellar", "NEAR": "NEAR Protocol",
        "APT": "Aptos", "ARB": "Arbitrum", "OP": "Optimism", "INJ": "Injective",
      };
      const coinName = coinNameMap[symbol.toUpperCase()] || symbol;
      
      const trendsData = await fetchCoinGoogleTrends(symbol, coinName);
      if (trendsData && trendsData.interestScore > 0) {
        googleTrendsContext = `
Google Trends (Retail Interest Signal):
- Search Interest: ${trendsData.interestScore}/100 (${trendsData.trend})
- Week-over-week Change: ${trendsData.weekChange > 0 ? "+" : ""}${trendsData.weekChange}%
- "Buy ${coinName}" searches: ${trendsData.buyInterest || "Low"}
- "${coinName} crash" searches: ${trendsData.sellInterest || "Low"}
NOTE: Rising search interest often precedes price moves. High "buy" searches = retail FOMO (often late). High "crash" searches = retail fear (contrarian bullish).`;
      }
    } catch (e) {
      console.log(`[getPricePrediction] Google Trends unavailable for ${symbol}`);
    }
    
    // Confidence guidelines vary by timeframe
    const getConfidenceGuidelines = (tf: string): string => {
      switch (tf) {
        case "1h":
          return `
1H CONFIDENCE SCALE:
- 70-85: Strong short-term signals (clear momentum, RSI extreme, volume spike)
- 50-70: Moderate signals (some indicators align)
- 30-50: Weak/conflicting signals
- <30: High uncertainty (choppy market, no clear direction)
1H predictions are MORE confident when short-term momentum is clear.`;
        case "4h":
          return `
4H CONFIDENCE SCALE:
- 65-80: Clear trend continuation or reversal signals
- 45-65: Moderate trend signals
- 25-45: Mixed signals, ranging market
- <25: High uncertainty
4H allows more confidence than longer timeframes.`;
        case "12h":
          return `
12H CONFIDENCE SCALE:
- 60-75: Strong half-day momentum alignment with clear trend
- 40-60: Moderate signals with some confirmation
- 20-40: Uncertain market conditions, mixed indicators
- <20: No clear direction
12H predictions bridge intraday and daily analysis - weight recent momentum heavily.`;
        case "24h":
          return `
24H CONFIDENCE SCALE:
- 55-70: Strong technical setup + sentiment alignment
- 35-55: Moderate signals with some conflict
- 20-35: Mixed signals, high uncertainty
- <20: No clear edge
24H predictions face more noise - be appropriately cautious.`;
        case "7d":
          return `
7D CONFIDENCE SCALE:
- 50-65: Strong weekly trend + fundamentals
- 30-50: Moderate weekly signals
- 15-30: Uncertain market regime
- <15: High uncertainty
7D predictions are inherently uncertain - max confidence ~65%.`;
        case "30d":
          return `
30D CONFIDENCE SCALE:
- 40-55: Very strong macro trend
- 25-40: Moderate long-term signals
- 10-25: High uncertainty
- <10: No clear long-term direction
30D predictions are most uncertain - max confidence ~55%.`;
        default:
          return `Confidence should reflect signal clarity and timeframe uncertainty.`;
      }
    };
    
    const systemPrompt = `You are a cryptocurrency price prediction analyst specializing in ${timeframe} predictions.

IMPORTANT: Confidence must VARY based on signal strength and clarity. DO NOT default to 50-70.

${getConfidenceGuidelines(timeframe)}

CONFIDENCE FACTORS:
+ Higher when: Multiple indicators agree, clear trend, volume confirms, sentiment extreme
- Lower when: Indicators conflict, choppy price action, low volume, neutral sentiment

Fear & Greed Impact:
- Extreme Fear (<25): Often bullish contrarian signal, can increase confidence for bullish calls
- Extreme Greed (>75): Often bearish contrarian signal, can increase confidence for bearish calls
- Neutral (40-60): Less predictive, lower confidence

Google Trends Impact (if available):
- Rising search interest (>+30% week): Retail attention increasing - can precede moves but be cautious of FOMO tops
- Falling search interest (<-30% week): Retail attention decreasing - can indicate accumulation phase
- High "buy [coin]" searches: Often late retail FOMO - can be contrarian bearish
- High "[coin] crash" searches: Retail fear - can be contrarian bullish signal
- Use as confirmation, not primary signal
${accuracyContext}
Provide predictions in JSON format:
{
  "direction": "bullish" | "bearish" | "neutral",
  "confidence": <number 10-85 based on guidelines above>,
  "priceRange": { "low": <negative % for downside>, "high": <positive % for upside> },
  "reasoning": "1-2 sentences explaining key factors"
}`;

    const userPrompt = `Predict ${symbol.toUpperCase()} price movement for the next ${timeframe}:
- Current Price: $${currentPrice?.toLocaleString() || "N/A"}
- Fear & Greed Index: ${fearGreedIndex ?? "N/A"} ${fearGreedIndex ? (fearGreedIndex < 25 ? "(Extreme Fear)" : fearGreedIndex > 75 ? "(Extreme Greed)" : fearGreedIndex < 40 ? "(Fear)" : fearGreedIndex > 60 ? "(Greed)" : "(Neutral)") : ""}
${technicalContext}
${googleTrendsContext}

Analyze the data and respond with JSON only. Remember: confidence should reflect actual signal clarity, not a default middle value.`;

    // Use DeepSeek client (or OpenAI fallback) - temperature 0.3 for more deterministic predictions
    const completion = await aiClient.chat.completions.create({
      model: modelUsed,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 400, // Slightly more tokens for DeepSeek's detailed reasoning
      temperature: 0.3, // Lower temperature for more consistent, analytical predictions
      response_format: { type: "json_object" },
    });

    let prediction;
    try {
      prediction = JSON.parse(completion.choices[0]?.message?.content || "{}");
    } catch {
      prediction = {
        direction: "neutral",
        confidence: 50,
        priceRange: { low: -5, high: 5 },
        reasoning: "Unable to parse prediction response.",
      };
    }
    
    // Validate and fix price range - AI sometimes returns 0/0 or missing range
    // This was causing the "0.00% change" bug in the app
    const defaultRanges: Record<string, { low: number; high: number }> = {
      "1h": { low: -1.5, high: 1.5 },
      "4h": { low: -3, high: 3 },
      "12h": { low: -4.5, high: 4.5 },
      "24h": { low: -5, high: 5 },
      "7d": { low: -12, high: 12 },
      "30d": { low: -20, high: 20 },
      "90d": { low: -30, high: 30 },
      "1y": { low: -50, high: 50 },
    };
    const defaultRange = defaultRanges[timeframe] || { low: -5, high: 5 };
    
    // Check if priceRange is missing, null, or has zero values
    const rangeIsBad = !prediction.priceRange ||
      (prediction.priceRange.low === 0 && prediction.priceRange.high === 0) ||
      (prediction.priceRange.low === undefined && prediction.priceRange.high === undefined);
    
    if (rangeIsBad) {
      console.log(`[getPricePrediction] ⚠️ Bad priceRange detected for ${symbol} (${timeframe}), inferring from direction: ${prediction.direction}`);
      
      // Infer range from direction
      if (prediction.direction === "bullish") {
        prediction.priceRange = {
          low: defaultRange.low * 0.3,   // Smaller downside
          high: defaultRange.high * 1.2,  // Larger upside
        };
      } else if (prediction.direction === "bearish") {
        prediction.priceRange = {
          low: defaultRange.low * 1.2,   // Larger downside
          high: defaultRange.high * 0.3,  // Smaller upside
        };
      } else {
        // Neutral - use symmetric but non-zero range
        prediction.priceRange = {
          low: defaultRange.low * 0.5,
          high: defaultRange.high * 0.5,
        };
      }
      console.log(`[getPricePrediction] 🔄 Fixed priceRange: ${JSON.stringify(prediction.priceRange)}`);
    }
    
    // Cache the result
    await cacheRef.set({
      prediction: prediction.direction,
      confidence: prediction.confidence,
      priceRange: prediction.priceRange,
      reasoning: prediction.reasoning,
      coinId,
      symbol: symbol.toUpperCase(),
      timeframe,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: modelUsed,
      tokens: completion.usage?.total_tokens || 0,
    });
    
    return {
      prediction: prediction.direction,
      confidence: prediction.confidence,
      priceRange: prediction.priceRange,
      reasoning: prediction.reasoning,
      cached: false,
      updatedAt: new Date().toISOString(),
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getPricePrediction");
  }
});

// ============================================================================
// AI TRADING SIGNAL
// ============================================================================

/**
 * Get AI-powered trading signal for a coin (BUY / SELL / HOLD)
 * 
 * Uses DeepSeek V3.2 to analyze technical indicators, market sentiment, and
 * momentum data to produce an actionable trading signal with reasoning.
 * 
 * SHARED across all users: cached in Firestore for 30 minutes per coin.
 * First request triggers the AI call, subsequent requests get the cached result.
 * 
 * Security: Rate limited, input validated, audit logged
 */
export const getTradingSignal = onCall({
  timeoutSeconds: 45,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const coinId = validateCoinId(request.data?.coinId);
    const symbol = validateCoinSymbol(request.data?.symbol);
    const currentPrice = request.data?.currentPrice ? validateNumber(request.data.currentPrice, 0, 10000000) : undefined;
    const fearGreedIndex = request.data?.fearGreedIndex ? validateNumber(request.data.fearGreedIndex, 0, 100) : undefined;
    const change24h = request.data?.change24h != null ? validateNumber(request.data.change24h, -100, 10000) : undefined;
    const change7d = request.data?.change7d != null ? validateNumber(request.data.change7d, -100, 10000) : undefined;
    const technicalIndicators = request.data?.technicalIndicators; // Optional object
    const isStock = coinId.startsWith("stock-");
    const isCommodity = coinId.startsWith("commodity-");
    
    // Keep crypto behavior unchanged; use shorter rolling cache buckets for stocks/commodities.
    const nonCryptoBucket = Math.floor(Date.now() / (10 * 60 * 1000));
    const cacheKey = (isStock || isCommodity)
      ? `signal_${coinId}_${nonCryptoBucket}`
      : `signal_${coinId}`;
    const cacheRef = db.collection("sharedAICache").doc(cacheKey);
    
    // Check cache first (30-minute TTL)
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.tradingSignal)) {
        return {
          signal: data.signal,
          confidence: data.confidence,
          confidenceScore: data.confidenceScore,
          reasoning: data.reasoning,
          keyFactors: data.keyFactors,
          sentimentScore: data.sentimentScore,
          riskLevel: data.riskLevel,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          model: data.model || "deepseek-chat",
        };
      }
    }
    
    // Cache miss - call DeepSeek for AI analysis
    // Audit log (costs money on cache miss)
    await logAuditEvent("ai_cache_miss", request, { function: "getTradingSignal", coinId, model: "deepseek-chat" });
    
    // Build technical context from client-provided indicators
    let technicalContext = "";
    if (technicalIndicators) {
      const parts: string[] = ["Current Technical Indicators:"];
      if (technicalIndicators.rsi != null) parts.push(`- RSI(14): ${sanitizeString(String(technicalIndicators.rsi), 30)}`);
      if (technicalIndicators.stochRSI) parts.push(`- Stoch RSI: ${sanitizeString(String(technicalIndicators.stochRSI), 50)}`);
      if (technicalIndicators.macdSignal) parts.push(`- MACD vs Signal: ${sanitizeString(String(technicalIndicators.macdSignal), 50)}`);
      if (technicalIndicators.macdHistogram) parts.push(`- MACD Histogram: ${sanitizeString(String(technicalIndicators.macdHistogram), 30)}`);
      if (technicalIndicators.sma20) parts.push(`- SMA(20): ${sanitizeString(String(technicalIndicators.sma20), 30)}`);
      if (technicalIndicators.sma50) parts.push(`- SMA(50): ${sanitizeString(String(technicalIndicators.sma50), 30)}`);
      if (technicalIndicators.ema12) parts.push(`- EMA(12): ${sanitizeString(String(technicalIndicators.ema12), 30)}`);
      if (technicalIndicators.ema26) parts.push(`- EMA(26): ${sanitizeString(String(technicalIndicators.ema26), 30)}`);
      if (technicalIndicators.bollingerPosition) parts.push(`- Bollinger Position: ${sanitizeString(String(technicalIndicators.bollingerPosition), 50)}`);
      if (technicalIndicators.adx != null) parts.push(`- ADX(14): ${sanitizeString(String(technicalIndicators.adx), 30)}`);
      if (technicalIndicators.volumeTrend) parts.push(`- Volume Trend: ${sanitizeString(String(technicalIndicators.volumeTrend), 30)}`);
      if (technicalIndicators.maTrend) parts.push(`- MA Structure: ${sanitizeString(String(technicalIndicators.maTrend), 40)}`);
      if (technicalIndicators.momentum7d) parts.push(`- 7D Momentum: ${sanitizeString(String(technicalIndicators.momentum7d), 30)}%`);
      technicalContext = parts.length > 1 ? parts.join("\n") : "";
    }
    
    const jsonFormat = `Respond with JSON only:
{
  "signal": "BUY" | "SELL" | "HOLD",
  "confidence": "High" | "Medium" | "Low",
  "confidenceScore": <number 10-90>,
  "reasoning": "<1-2 sentence natural language analysis explaining the signal>",
  "keyFactors": ["<factor 1>", "<factor 2>", ...],
  "sentimentScore": <number -1.0 to 1.0>,
  "riskLevel": "Low" | "Medium" | "High"
}`;
    
    let systemPrompt: string;
    
    if (isStock) {
      systemPrompt = `You are an expert equity/stock trading signal analyst for CryptoSage AI. Your job is to analyze technical indicators, price action, and market conditions to produce a clear BUY, SELL, or HOLD trading signal for stocks and ETFs.

SIGNAL CRITERIA:
- BUY: Multiple bullish indicators align (oversold RSI, bullish MACD crossover, price above key MAs, positive earnings momentum, sector strength)
- SELL: Multiple bearish indicators align (overbought RSI, bearish MACD, price below key MAs, declining fundamentals, sector weakness)
- HOLD: Mixed or weak signals, no clear directional edge, conflicting indicators

CONFIDENCE SCORING (10-90):
- 70-90 (High): 4+ indicators strongly agree, clear trend, volume confirms
- 50-69 (Medium): 2-3 indicators agree, moderate trend
- 10-49 (Low): Mixed signals, choppy action, few indicators agree

SENTIMENT SCORE (-1.0 to 1.0):
- Maps the overall reading from strongly bearish (-1.0) to strongly bullish (1.0)

RISK LEVEL:
- Low: Clear trend, low volatility, strong indicator agreement
- Medium: Moderate signals, normal volatility
- High: Conflicting signals, high volatility, earnings risk, sector rotation risk

KEY FACTORS: List the 2-4 most important reasons driving the signal (technical, sector, valuation).

${jsonFormat}`;
    } else if (isCommodity) {
      systemPrompt = `You are an expert commodities trading signal analyst for CryptoSage AI. Your job is to analyze technical indicators, supply/demand dynamics, and price action to produce a clear BUY, SELL, or HOLD trading signal for commodities (gold, oil, natural gas, etc.).

SIGNAL CRITERIA:
- BUY: Multiple bullish indicators align (oversold RSI, bullish MACD, price above key MAs, supply constraints, geopolitical risk premium, seasonal strength)
- SELL: Multiple bearish indicators align (overbought RSI, bearish MACD, price below key MAs, demand weakness, supply surplus)
- HOLD: Mixed or weak signals, no clear directional edge, conflicting indicators

CONFIDENCE SCORING (10-90):
- 70-90 (High): 4+ indicators strongly agree, clear trend, volume confirms
- 50-69 (Medium): 2-3 indicators agree, moderate trend
- 10-49 (Low): Mixed signals, choppy action, few indicators agree

SENTIMENT SCORE (-1.0 to 1.0):
- Maps the overall reading from strongly bearish (-1.0) to strongly bullish (1.0)

RISK LEVEL:
- Low: Clear trend, low volatility, strong indicator agreement
- Medium: Moderate signals, normal volatility
- High: Conflicting signals, high volatility, geopolitical uncertainty, seasonal transition

KEY FACTORS: List the 2-4 most important reasons driving the signal (technical, supply/demand, macro).

${jsonFormat}`;
    } else {
      systemPrompt = `You are an expert cryptocurrency trading signal analyst for CryptoSage AI. Your job is to analyze technical indicators, market sentiment, and price action to produce a clear BUY, SELL, or HOLD trading signal.

SIGNAL CRITERIA:
- BUY: Multiple bullish indicators align (oversold RSI, bullish MACD crossover, price above key MAs, positive momentum, fear in market = contrarian buy)
- SELL: Multiple bearish indicators align (overbought RSI, bearish MACD, price below key MAs, negative momentum, extreme greed = contrarian sell)
- HOLD: Mixed or weak signals, no clear directional edge, conflicting indicators

CONFIDENCE SCORING (10-90):
- 70-90 (High): 4+ indicators strongly agree, clear trend, volume confirms
- 50-69 (Medium): 2-3 indicators agree, moderate trend
- 10-49 (Low): Mixed signals, choppy action, few indicators agree

SENTIMENT SCORE (-1.0 to 1.0):
- Maps the overall reading from strongly bearish (-1.0) to strongly bullish (1.0)
- Should reflect the weight and alignment of all indicators, not just the signal

RISK LEVEL:
- Low: Clear trend, low volatility, strong indicator agreement
- Medium: Moderate signals, normal volatility
- High: Conflicting signals, high volatility, extreme RSI, major news risk

KEY FACTORS: List the 2-4 most important technical reasons driving the signal.

Fear & Greed Impact:
- Extreme Fear (<25): Contrarian bullish signal - smart money accumulates during fear
- Extreme Greed (>75): Contrarian bearish signal - markets tend to correct after euphoria
- Neutral (40-60): Less predictive, lower weight

${jsonFormat}`;
    }

    const assetLabel = isStock ? "stock/ETF" : isCommodity ? "commodity" : "cryptocurrency";
    const userPrompt = `Analyze the ${assetLabel} ${symbol.toUpperCase()} and provide a trading signal:
- Current Price: $${currentPrice?.toLocaleString() || "N/A"}
- 24H Change: ${change24h != null ? (change24h > 0 ? "+" : "") + change24h.toFixed(2) + "%" : "N/A"}
- 7D Change: ${change7d != null ? (change7d > 0 ? "+" : "") + change7d.toFixed(2) + "%" : "N/A"}${!isStock && !isCommodity && fearGreedIndex ? `\n- Fear & Greed Index: ${fearGreedIndex} ${fearGreedIndex < 25 ? "(Extreme Fear)" : fearGreedIndex > 75 ? "(Extreme Greed)" : fearGreedIndex < 40 ? "(Fear)" : fearGreedIndex > 60 ? "(Greed)" : "(Neutral)"}` : ""}
${technicalContext}

Analyze ALL available data holistically. Respond with JSON only.`;

    // Use callAIWithFallback (DeepSeek -> OpenRouter -> OpenAI)
    const aiResult = await callAIWithFallback({
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 350,
      temperature: 0.2, // Low temperature for consistent, analytical signals
      response_format: { type: "json_object" },
      functionName: "getTradingSignal",
    });

    let parsed;
    try {
      parsed = JSON.parse(aiResult.content);
    } catch {
      parsed = {
        signal: "HOLD",
        confidence: "Low",
        confidenceScore: 40,
        reasoning: "Unable to parse AI response. Defaulting to HOLD.",
        keyFactors: ["Analysis unavailable"],
        sentimentScore: 0,
        riskLevel: "Medium",
      };
    }
    
    // Validate and normalize the response
    const validSignals = ["BUY", "SELL", "HOLD"];
    const signal = validSignals.includes(parsed.signal?.toUpperCase()) ? parsed.signal.toUpperCase() : "HOLD";
    const confidenceLabel = ["High", "Medium", "Low"].includes(parsed.confidence) ? parsed.confidence : "Low";
    const confidenceScore = Math.max(10, Math.min(90, parsed.confidenceScore || 40));
    const sentimentScore = Math.max(-1, Math.min(1, parsed.sentimentScore || 0));
    const riskLevel = ["Low", "Medium", "High"].includes(parsed.riskLevel) ? parsed.riskLevel : "Medium";
    const reasoning = sanitizeString(parsed.reasoning || "Analysis complete.", 300);
    const keyFactors = Array.isArray(parsed.keyFactors) 
      ? parsed.keyFactors.slice(0, 5).map((f: string) => sanitizeString(String(f), 80))
      : ["Technical analysis"];
    
    // Cache the result in Firestore (shared across all users)
    await cacheRef.set({
      signal,
      confidence: confidenceLabel,
      confidenceScore,
      reasoning,
      keyFactors,
      sentimentScore,
      riskLevel,
      coinId,
      symbol: symbol.toUpperCase(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: aiResult.model,
      provider: aiResult.provider,
      tokens: aiResult.tokens,
    });
    
    return {
      signal,
      confidence: confidenceLabel,
      confidenceScore,
      reasoning,
      keyFactors,
      sentimentScore,
      riskLevel,
      cached: false,
      updatedAt: new Date().toISOString(),
      model: aiResult.model,
    };
  } catch (error) {
    throw safeError(error, "getTradingSignal");
  }
});

// ============================================================================
// PREDICTION ACCURACY TRACKING
// ============================================================================

/**
 * Record a prediction outcome for global accuracy tracking
 * Called when a user views a prediction - tracks the prediction for later evaluation
 * 
 * Security: Rate limited, input validated
 * Privacy: No user identification, only prediction data
 */
export const recordPredictionOutcome = onCall({
  timeoutSeconds: 10,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting (prevent spam)
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const coinId = validateCoinId(request.data?.coinId);
    const symbol = validateCoinSymbol(request.data?.symbol);
    const timeframe = validateTimeframe(request.data?.timeframe);
    const direction = sanitizeString(request.data?.direction || "", 20);
    const confidence = validateNumber(request.data?.confidence, 0, 100);
    const priceAtPrediction = validateNumber(request.data?.priceAtPrediction, 0, 10000000);
    const priceLow = request.data?.priceLow ? validateNumber(request.data.priceLow, -100, 100) : null;
    const priceHigh = request.data?.priceHigh ? validateNumber(request.data.priceHigh, -100, 100) : null;
    
    // Validate direction
    if (!["bullish", "bearish", "neutral"].includes(direction)) {
      throw new HttpsError("invalid-argument", "Invalid direction");
    }
    
    // Calculate target date based on timeframe
    const now = new Date();
    const targetDate = new Date(now);
    switch (timeframe) {
      case "1h": targetDate.setHours(targetDate.getHours() + 1); break;
      case "4h": targetDate.setHours(targetDate.getHours() + 4); break;
      case "12h": targetDate.setHours(targetDate.getHours() + 12); break;
      case "24h": targetDate.setDate(targetDate.getDate() + 1); break;
      case "7d": targetDate.setDate(targetDate.getDate() + 7); break;
      case "30d": targetDate.setDate(targetDate.getDate() + 30); break;
      default: targetDate.setDate(targetDate.getDate() + 1); // Default to 24h
    }
    
    // Create cache key to match with prediction
    const predictionCacheKey = `prediction_${coinId}_${timeframe}`;
    
    // Check if we already have a recent outcome for this prediction
    // (within the last few minutes - prevents duplicate recordings)
    const recentOutcomes = await db.collection("predictionOutcomes")
      .where("predictionCacheKey", "==", predictionCacheKey)
      .where("predictedAt", ">", admin.firestore.Timestamp.fromDate(new Date(now.getTime() - 5 * 60 * 1000)))
      .limit(1)
      .get();
    
    if (!recentOutcomes.empty) {
      // Already recorded recently, return success without creating duplicate
      return { 
        success: true, 
        message: "Prediction already recorded",
        outcomeId: recentOutcomes.docs[0].id
      };
    }
    
    // Store the prediction outcome for later evaluation
    const outcomeRef = await db.collection("predictionOutcomes").add({
      predictionCacheKey,
      coinId,
      symbol: symbol.toUpperCase(),
      timeframe,
      direction,
      confidence,
      priceAtPrediction,
      priceRangeLow: priceLow,
      priceRangeHigh: priceHigh,
      predictedAt: admin.firestore.FieldValue.serverTimestamp(),
      targetDate: admin.firestore.Timestamp.fromDate(targetDate),
      // These will be filled in by the evaluation function
      actualPrice: null,
      actualDirection: null,
      wasCorrect: null,
      withinRange: null,
      priceError: null,
      evaluatedAt: null,
    });
    
    return { 
      success: true, 
      outcomeId: outcomeRef.id,
      targetDate: targetDate.toISOString()
    };
  } catch (error) {
    throw safeError(error, "recordPredictionOutcome");
  }
});

// ============================================================================
// DEEPSEEK CONSULTATION FOR AI CHAT
// ============================================================================

/**
 * Consult DeepSeek for a crypto-specific analysis to augment ChatGPT responses.
 * 
 * This is the "multi-AI consultation" bridge: ChatGPT calls this before responding
 * to financial queries so it can incorporate DeepSeek's crypto-specialist opinion.
 * 
 * - Accepts: user query, coin symbol(s), market context snippet
 * - Returns: structured JSON with direction, confidence, key levels, risks, reasoning
 * - Caches results in Firestore for 15 minutes per coin+query-type
 * - Falls back gracefully (returns empty if DeepSeek is down)
 * 
 * Security: Rate limited, input validated, audit logged
 */
export const consultDeepSeek = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const userQuery = sanitizeString(request.data?.query || "", 500);
    const coins = (request.data?.coins || []) as Array<{ symbol: string; name?: string; price?: number; change24h?: number }>;
    const marketContext = sanitizeString(request.data?.marketContext || "", 1000);
    
    if (!userQuery || coins.length === 0) {
      // Return empty — ChatGPT proceeds without DeepSeek input
      return { consultation: null, reason: "no_query_or_coins" };
    }
    
    // Validate & sanitize coin list (max 3 coins)
    const validCoins = coins.slice(0, 3).map(c => ({
      symbol: sanitizeString(c.symbol || "", 10).toUpperCase(),
      name: sanitizeString(c.name || c.symbol || "", 50),
      price: c.price ? validateNumber(c.price, 0, 10000000) : undefined,
      change24h: c.change24h != null ? validateNumber(c.change24h, -100, 10000) : undefined,
    }));
    
    // Build cache key from coins + query category (not full query, to allow cache hits)
    const coinKey = validCoins.map(c => c.symbol).sort().join("_");
    const queryCategory = categorizeQuery(userQuery);
    const timeBucket = Math.floor(Date.now() / (15 * 60 * 1000)); // 15-minute buckets
    const cacheKey = `consult_${coinKey}_${queryCategory}_${timeBucket}`;
    const cacheRef = db.collection("sharedAICache").doc(cacheKey);
    
    // Check cache first (15-minute TTL via time bucket in key)
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && data.consultation) {
        return {
          consultation: data.consultation,
          cached: true,
          model: data.model || "deepseek-chat",
        };
      }
    }
    
    // Cache miss — call DeepSeek
    const { client: aiClient, model: modelUsed, provider: aiProvider } = getDeepSeekClient();
    
    // Audit log
    await logAuditEvent("ai_cache_miss", request, { 
      function: "consultDeepSeek", coins: coinKey, category: queryCategory, model: modelUsed, provider: aiProvider 
    });
    
    // Build coin context
    const coinContext = validCoins.map(c => {
      let info = `${c.name} (${c.symbol})`;
      if (c.price) info += ` — Current price: $${c.price.toLocaleString()}`;
      if (c.change24h != null) info += `, 24h change: ${c.change24h >= 0 ? "+" : ""}${c.change24h.toFixed(2)}%`;
      return info;
    }).join("\n");
    
    const systemPrompt = `You are DeepSeek, a specialized cryptocurrency analyst integrated into the CryptoSage AI system. Another AI (ChatGPT) will use your analysis to provide a comprehensive answer to the user. Be direct, data-driven, and specific.

Your role: Provide expert crypto market analysis that ChatGPT can synthesize into its response.

Respond with JSON only:
{
  "direction": "bullish" | "bearish" | "neutral",
  "confidence": <number 1-100>,
  "shortTermOutlook": "<1 sentence: next 24-48h expectation>",
  "mediumTermOutlook": "<1 sentence: next 1-2 week expectation>",
  "keyLevels": {
    "support": [<up to 2 key support prices>],
    "resistance": [<up to 2 key resistance prices>]
  },
  "risks": ["<top risk 1>", "<top risk 2>"],
  "reasoning": "<2-3 sentence analysis covering technicals, sentiment, and catalysts>",
  "suggestedAction": "<specific actionable recommendation e.g. 'Accumulate on dips to $X support' or 'Take partial profits above $X'>"
}

Rules:
- Base analysis on current price action, market cycle position, and known patterns
- Be honest about uncertainty — don't inflate confidence
- Key levels should be realistic price points, not percentages
- If you don't have enough data for key levels, omit them or use null
- Keep reasoning concise but specific`;

    const userPrompt = `User question: "${userQuery}"

Coins to analyze:
${coinContext}

${marketContext ? `Current market context:\n${marketContext}` : ""}

Provide your expert crypto analysis for these coins in the context of the user's question.`;

    const completion = await aiClient.chat.completions.create({
      model: modelUsed,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 400,
      temperature: 0.3,
      response_format: { type: "json_object" },
    });
    
    const responseText = completion.choices[0]?.message?.content || "";
    
    let consultation;
    try {
      consultation = JSON.parse(responseText);
    } catch {
      // If JSON parsing fails, return the raw text as reasoning
      consultation = {
        direction: "neutral",
        confidence: 50,
        reasoning: responseText.slice(0, 500),
        suggestedAction: "Review the analysis and make your own determination.",
      };
    }
    
    // Cache the result
    await cacheRef.set({
      consultation,
      model: modelUsed,
      provider: aiProvider,
      query: userQuery.slice(0, 200), // Store truncated query for debugging
      coins: coinKey,
      category: queryCategory,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return {
      consultation,
      cached: false,
      model: modelUsed,
    };
    
  } catch (error) {
    // DeepSeek consultation is non-critical — log and return empty
    console.error("[consultDeepSeek] Error:", error instanceof Error ? error.message : "Unknown error");
    await logAuditEvent("consult_deepseek_error", request, {
      error: error instanceof Error ? error.message : "Unknown error"
    }, "warning");
    
    // Return empty consultation — ChatGPT proceeds without it
    return { consultation: null, reason: "error", cached: false };
  }
});

/**
 * Categorize a user query into a broad bucket for cache key purposes.
 * This allows similar queries to hit the same cache.
 */
function categorizeQuery(query: string): string {
  const q = query.toLowerCase();
  if (q.match(/buy|sell|trade|entry|exit|position/)) return "trade";
  if (q.match(/predict|forecast|target|where.*go|moon|dump|crash|pump|rally/)) return "prediction";
  if (q.match(/risk|safe|danger|worry|concern|hedge/)) return "risk";
  if (q.match(/support|resistance|level|technical|chart|pattern/)) return "technicals";
  if (q.match(/hold|hodl|long.?term|invest|dca|accumulate/)) return "investment";
  return "general";
}

/**
 * Get Fear & Greed commentary (AI-enhanced)
 * This is SHARED across all users with similar F&G values
 * 
 * Security: Rate limited, input validated, audit logged
 */
export const getFearGreedCommentary = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicAI");
    
    // Input validation
    const rawValue = request.data?.value;
    if (rawValue === undefined || rawValue === null) {
      throw new HttpsError("invalid-argument", "Fear & Greed value is required");
    }
    const value = validateNumber(rawValue, 0, 100);
    const classification = request.data?.classification ? sanitizeString(request.data.classification, 50) : "Neutral";
    
    const cacheRef = db.collection("sharedAICache").doc("fearGreedCommentary");
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      // Only use cache if the value is similar (within 5 points)
      if (data && 
          isCacheValid(data.updatedAt, CACHE_DURATIONS.fearGreedCommentary) &&
          Math.abs(data.value - value) <= 5) {
        return {
          commentary: data.commentary,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
          model: data.model || "gpt-4o",
        };
      }
    }
    
    // Cache miss - call AI (DeepSeek preferred for crypto analysis, with fallback chain)
    const systemPrompt = `You provide brief, actionable commentary on the Crypto Fear & Greed Index.
Keep responses to 1-2 sentences. Be practical and avoid excessive drama.`;

    const userPrompt = `The Crypto Fear & Greed Index is currently at ${value} (${classification}).
What does this mean for traders in 1-2 sentences?`;

    let commentary: string;
    let modelUsed: string;
    let providerUsed = "none";

    try {
      const aiResult = await callAIWithFallback({
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 100,
        temperature: 0.7,
        functionName: "getFearGreedCommentary",
      });
      modelUsed = aiResult.model;
      providerUsed = aiResult.provider;
      commentary = aiResult.content || "Unable to generate commentary.";
    } catch (aiError) {
      // All AI providers failed — return stale cache or static fallback
      console.error("[getFearGreedCommentary] All AI providers failed, using fallback:", aiError);

      // Try returning expired cache
      const staleCache = await cacheRef.get();
      if (staleCache.exists) {
        const data = staleCache.data();
        if (data?.commentary) {
          return {
            commentary: data.commentary,
            cached: true,
            updatedAt: data.updatedAt?.toDate?.()?.toISOString?.() || new Date().toISOString(),
            model: data.model || "stale-cache",
          };
        }
      }

      // Generate a simple template-based commentary without AI
      if (value < 20) {
        commentary = `Extreme fear at ${value} often signals potential buying opportunities, as markets tend to overreact to negative sentiment.`;
      } else if (value < 40) {
        commentary = `Fear at ${value} suggests cautious sentiment. Historically, moderate fear can precede market recoveries.`;
      } else if (value < 60) {
        commentary = `Neutral sentiment at ${value} indicates balanced market conditions with no strong directional bias.`;
      } else if (value < 80) {
        commentary = `Greed at ${value} suggests growing optimism. Consider taking partial profits as sentiment heats up.`;
      } else {
        commentary = `Extreme greed at ${value} signals potential overextension. Exercise caution as markets may be due for a correction.`;
      }
      modelUsed = "template-fallback";
    }

    // Cache and return (only cache AI-generated results)
    if (modelUsed !== "template-fallback") {
      await logAuditEvent("ai_cache_miss", request, { function: "getFearGreedCommentary", value, provider: providerUsed });

      await cacheRef.set({
        commentary,
        value,
        classification,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        model: modelUsed,
        provider: providerUsed,
      });
    }

    return {
      commentary,
      cached: modelUsed === "template-fallback",
      updatedAt: new Date().toISOString(),
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getFearGreedCommentary");
  }
});

/**
 * Portfolio insight - PERSONALIZED per user
 * Requires authentication
 * 
 * Security: Authenticated, input validation, rate limiting, usage tracking, audit logged
 */
export const getPortfolioInsight = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
  secrets: ["OPENAI_API_KEY"],
}, async (request) => {
  try {
    // Authentication required
    const userId = await validateAuth(request);
    if (!userId) {
      await logAuditEvent("unauthorized_access", request, { function: "getPortfolioInsight" }, "warning");
      throw new HttpsError("unauthenticated", "Authentication required for portfolio insights");
    }
    
    // Rate limiting (per user)
    await checkRateLimit(userId, "userPortfolio");
    
    // Verify subscription
    const subscription = await verifySubscription(userId);
    const limits = getTierLimits(subscription.tier);
    
    // Input validation
    const holdings = validateHoldings(request.data?.holdings || []);
    const totalValue = validateNumber(request.data?.totalValue, 0, 1e15);
    const btcDominance = validateNumber(request.data?.btcDominance, 0, 100, 0);
    // marketCap validated but used only for future features
    const _marketCap = validateNumber(request.data?.marketCap, 0, 1e18);
    void _marketCap; // Suppress unused warning
    
    if (holdings.length === 0) {
      return {
        content: "Add some holdings to get personalized portfolio insights.",
        cached: false,
        usageRemaining: limits.dailyPortfolioInsights,
        model: limits.usePremiumModel ? "gpt-4o" : "gpt-4o-mini",
      };
    }
    
    // Check usage count for today
    const today = new Date().toISOString().split("T")[0];
    const usageRef = db.collection("users").doc(userId).collection("usage").doc(today);
    const usageDoc = await usageRef.get();
    const currentUsage = usageDoc.exists ? (usageDoc.data()?.portfolioInsights || 0) : 0;
    
    if (currentUsage >= limits.dailyPortfolioInsights) {
      await logAuditEvent("usage_limit_reached", request, { 
        function: "getPortfolioInsight", 
        tier: subscription.tier,
        limit: limits.dailyPortfolioInsights 
      }, "info");
      
      throw new HttpsError(
        "resource-exhausted", 
        `Daily limit reached (${limits.dailyPortfolioInsights} insights). Upgrade for more.`
      );
    }
    
    const openai = getOpenAIClient();
    
    // OPTIMIZED: Varied insight types for freshness, specific guidance for quality
    const insightTypes = ["risk assessment", "rebalancing opportunity", "market timing", "concentration risk", "momentum play"];
    const focusType = insightTypes[Math.floor(Math.random() * insightTypes.length)];
    
    const systemPrompt = `You are a crypto portfolio analyst. Give ONE specific, actionable insight in 2 sentences max.
Focus on: ${focusType}.
Rules:
- Be specific (mention actual coins from their holdings)
- Give a concrete action (buy, sell, hold, rebalance)
- Never be generic like "diversify more" without specifics
- Never mention exact dollar amounts for privacy`;

    // Compact holdings format (saves tokens)
    const compactHoldings = holdings
      .slice(0, 8)
      .map((h) => `${h.symbol} ${((h.value / totalValue) * 100).toFixed(0)}% (${h.change24h >= 0 ? "+" : ""}${h.change24h.toFixed(1)}%)`)
      .join(", ");

    const userPrompt = `Holdings: ${compactHoldings}${holdings.length > 8 ? ` +${holdings.length - 8} more` : ""}
Market: BTC dom ${btcDominance.toFixed(0)}%`;

    // Platinum users get GPT-4o for all features (including personalized content)
    // At $59.99/month with ~$18.60 max cost, margin is still 69%
    const modelUsed = limits.usePremiumModel ? "gpt-4o" : "gpt-4o-mini";
    
    const completion = await openai.chat.completions.create({
      model: modelUsed,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 256,
      temperature: 0.7,
    });

    const content = completion.choices[0]?.message?.content || "Unable to generate portfolio insight.";
    
    // Increment usage counter
    await usageRef.set({
      portfolioInsights: admin.firestore.FieldValue.increment(1),
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    
    // Audit log for successful insight generation
    await logAuditEvent("portfolio_insight_generated", request, {
      tier: subscription.tier,
      holdingsCount: holdings.length,
      usageAfter: currentUsage + 1,
      model: modelUsed,
    });
    
    return {
      content,
      cached: false,
      usageRemaining: limits.dailyPortfolioInsights - currentUsage - 1,
      model: modelUsed,
    };
  } catch (error) {
    throw safeError(error, "getPortfolioInsight");
  }
});

// ============================================================================
// AI CHAT FUNCTION
// ============================================================================

/**
 * Send a chat message and get AI response
 * This powers the AI Chat feature for ALL users
 * 
 * Security: Rate limited, input validated, subscription-aware, audit logged
 */
export const sendChatMessage = onCall({
  timeoutSeconds: 90,
  memory: "512MiB",
  secrets: ["OPENAI_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  const userId = request.auth?.uid || null;
  
  try {
    // Rate limiting - use user ID if authenticated, otherwise IP
    const rateLimitKey = userId || clientIP;
    await checkRateLimit(rateLimitKey, userId ? "userAI" : "publicAI");
    
    // Input validation
    const userMessage = sanitizeString(request.data?.message, 4000);
    if (!userMessage || userMessage.length < 1) {
      throw new HttpsError("invalid-argument", "Message is required");
    }
    
    // Validate conversation history (optional)
    const rawHistory = request.data?.history;
    let conversationHistory: Array<{role: string; content: string}> = [];
    
    if (Array.isArray(rawHistory)) {
      // Limit history to last 20 messages to control token usage
      conversationHistory = rawHistory.slice(-20).map((msg: unknown) => {
        if (typeof msg !== "object" || msg === null) {
          return null;
        }
        const m = msg as Record<string, unknown>;
        const role = m.role === "assistant" ? "assistant" : "user";
        const content = sanitizeString(m.content, 2000);
        return content ? { role, content } : null;
      }).filter((m): m is {role: string; content: string} => m !== null);
    }
    
    // Check subscription for model selection
    let modelUsed = "gpt-4o-mini"; // Default for free/pro users
    let maxTokens = 1024;
    
    if (userId) {
      const subscription = await verifySubscription(userId);
      const limits = getTierLimits(subscription.tier);
      
      if (limits.usePremiumModel) {
        modelUsed = "gpt-4o"; // Premium users get GPT-4o
        maxTokens = 2048;
      }
    }
    
    // Use custom system prompt if provided (contains portfolio/market context from app)
    // Otherwise fall back to default prompt
    const customSystemPrompt = request.data?.systemPrompt ? sanitizeString(request.data.systemPrompt, 16000) : null;
    
    const defaultSystemPrompt = `You are CryptoSage AI, a knowledgeable and helpful cryptocurrency assistant. 
You provide accurate, up-to-date information about cryptocurrency markets, trading strategies, 
blockchain technology, and DeFi. 

Guidelines:
- Be concise but thorough
- Provide actionable insights when relevant
- Acknowledge uncertainty when appropriate
- Never provide financial advice - always recommend users do their own research
- Use plain text formatting (no markdown) for mobile readability`;

    // Use the rich context system prompt from the app if available
    const systemPrompt = customSystemPrompt || defaultSystemPrompt;

    const messages: Array<{role: "system" | "user" | "assistant"; content: string}> = [
      { role: "system", content: systemPrompt },
      ...conversationHistory.map(m => ({
        role: m.role as "user" | "assistant",
        content: m.content
      })),
      { role: "user", content: userMessage }
    ];
    
    // Call OpenAI
    const openai = getOpenAIClient();
    
    const completion = await openai.chat.completions.create({
      model: modelUsed,
      messages,
      max_tokens: maxTokens,
      temperature: 0.7,
    });
    
    const responseText = completion.choices[0]?.message?.content || "I apologize, but I couldn't generate a response. Please try again.";
    
    // Audit log for chat usage (anonymized)
    await logAuditEvent("chat_message_sent", request, {
      model: modelUsed,
      inputLength: userMessage.length,
      outputLength: responseText.length,
      historyLength: conversationHistory.length,
      tokens: completion.usage?.total_tokens || 0,
    });
    
    return {
      response: responseText,
      model: modelUsed,
      tokens: completion.usage?.total_tokens || 0,
    };
  } catch (error) {
    // Log the error
    await logAuditEvent("chat_error", request, {
      error: error instanceof Error ? error.message : "Unknown error"
    }, "error");
    
    throw safeError(error, "sendChatMessage");
  }
});

/**
 * Send a chat message with streaming response (HTTP endpoint)
 * Returns Server-Sent Events for real-time streaming
 * 
 * Security: Rate limited, input validated, audit logged
 */
export const streamChatMessage = onRequest({
  timeoutSeconds: 90,
  memory: "512MiB",
  cors: true,
  secrets: ["OPENAI_API_KEY"],
}, async (req, res) => {
  // Only accept POST
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  
  const clientIP = req.headers["x-forwarded-for"]?.toString().split(",")[0].trim() || req.ip || "unknown";
  
  try {
    // Parse request body - extract systemPrompt along with message and history
    const { message, history, systemPrompt: customSystemPrompt } = req.body?.data || req.body || {};
    
    // Input validation
    const userMessage = sanitizeString(message, 4000);
    if (!userMessage || userMessage.length < 1) {
      res.status(400).json({ error: "Message is required" });
      return;
    }
    
    // Validate conversation history
    let conversationHistory: Array<{role: string; content: string}> = [];
    if (Array.isArray(history)) {
      conversationHistory = history.slice(-20).map((msg: unknown) => {
        if (typeof msg !== "object" || msg === null) return null;
        const m = msg as Record<string, unknown>;
        const role = m.role === "assistant" ? "assistant" : "user";
        const content = sanitizeString(m.content, 2000);
        return content ? { role, content } : null;
      }).filter((m): m is {role: string; content: string} => m !== null);
    }
    
    // Use custom system prompt if provided (contains portfolio/market context from app)
    // Sanitize and limit the custom prompt to prevent abuse
    const sanitizedCustomPrompt = customSystemPrompt ? sanitizeString(customSystemPrompt, 16000) : null;
    
    const defaultSystemPrompt = `You are CryptoSage AI, a knowledgeable cryptocurrency assistant. 
Be concise, accurate, and helpful. Use plain text (no markdown) for mobile readability.
Never provide financial advice - recommend users do their own research.`;

    // Use the rich context system prompt from the app if available
    const systemPrompt = sanitizedCustomPrompt || defaultSystemPrompt;

    const messages: Array<{role: "system" | "user" | "assistant"; content: string}> = [
      { role: "system", content: systemPrompt },
      ...conversationHistory.map(m => ({
        role: m.role as "user" | "assistant",
        content: m.content
      })),
      { role: "user", content: userMessage }
    ];
    
    // Set up SSE headers
    res.setHeader("Content-Type", "text/event-stream");
    res.setHeader("Cache-Control", "no-cache");
    res.setHeader("Connection", "keep-alive");
    res.setHeader("X-Accel-Buffering", "no");
    
    // Call OpenAI with streaming
    const openai = getOpenAIClient();
    const modelUsed = "gpt-4o-mini"; // Use cost-effective model for streaming
    
    const stream = await openai.chat.completions.create({
      model: modelUsed,
      messages,
      max_tokens: 1024,
      temperature: 0.7,
      stream: true,
    });
    
    let fullResponse = "";
    
    for await (const chunk of stream) {
      const content = chunk.choices[0]?.delta?.content || "";
      if (content) {
        fullResponse += content;
        // Send SSE event
        res.write(`data: ${JSON.stringify({ content, done: false })}\n\n`);
      }
    }
    
    // Send completion event
    res.write(`data: ${JSON.stringify({ content: "", done: true, fullResponse })}\n\n`);
    res.end();
    
    // Log chat usage (after response sent)
    console.log(`[Chat] IP: ${clientIP.substring(0, 8)}***, Model: ${modelUsed}, Input: ${userMessage.length}c, Output: ${fullResponse.length}c`);
    
  } catch (error) {
    console.error("[streamChatMessage] Error:", error);
    
    // Try to send error via SSE if possible
    try {
      res.write(`data: ${JSON.stringify({ error: "An error occurred. Please try again.", done: true })}\n\n`);
      res.end();
    } catch {
      // Response already sent, just log
      res.status(500).json({ error: "Internal server error" });
    }
  }
});

// ============================================================================
// MARKET DATA PROXY FUNCTIONS
// ============================================================================

/**
 * Proxy CoinGecko markets API with caching
 * Reduces rate limit hits by caching responses
 * 
 * Security: Rate limited, input validated
 */
export const getCoinGeckoMarkets = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Input validation with bounds
    const page = validateNumber(request.data?.page ?? 1, 1, 100, 1);
    const perPage = validateNumber(request.data?.perPage ?? 100, 1, 250, 100); // CoinGecko max is 250
    const sparkline = request.data?.sparkline !== false; // Default true
    
    const cacheKey = `coingecko_markets_${page}_${perPage}_${sparkline}`;
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.coinGeckoMarkets)) {
        return {
          coins: data.coins,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // SCALABILITY FIX: Request coalescing - only one request fetches from API
    // If another request is already fetching, wait for it to complete
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache to be populated
      console.log(`[getCoinGeckoMarkets] Waiting for another request to complete fetch for ${cacheKey}`);
      const { data, timedOut } = await waitForCachedData(cacheRef, CACHE_DURATIONS.coinGeckoMarkets);
      
      if (data && !timedOut) {
        return {
          coins: data.coins,
          cached: true,
          coalesced: true, // Indicate this was a coalesced request
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
      
      // Timed out waiting, fall through to fetch ourselves
      console.log(`[getCoinGeckoMarkets] Wait timed out, proceeding with fetch`);
    }
    
    // RATE LIMIT FIX: Try Firestore coingeckoMarkets first (for page 1, default params)
    if (page === 1 && perPage >= 100 && sparkline) {
      const firestoreCG = await db.collection("marketData").doc("coingeckoMarkets").get();
      if (firestoreCG.exists) {
        const fsData = firestoreCG.data();
        const syncedAt = fsData?.updatedAt?.toDate?.() || new Date(fsData?.syncedAt || 0);
        const ageMs = Date.now() - syncedAt.getTime();
        
        if (ageMs < 10 * 60 * 1000 && Array.isArray(fsData?.coins) && fsData.coins.length > 0) {
          console.log(`[getCoinGeckoMarkets] Using Firestore data (${fsData.coins.length} coins, ${Math.round(ageMs / 1000)}s old)`);
          const coins = fsData.coins.slice(0, perPage);
          
          // Cache for future requests
          await cacheRef.set({
            coins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          
          if (acquiredLock) await releaseFetchLock(cacheKey);
          
          return {
            coins,
            cached: true,
            firestoreSource: true,
            updatedAt: fsData.updatedAt?.toDate?.()?.toISOString() || fsData.syncedAt,
          };
        }
      }
    }
    
    // Cache miss - fetch from CoinGecko (tracked)
    try {
      const url = new URL("https://api.coingecko.com/api/v3/coins/markets");
      url.searchParams.set("vs_currency", "usd");
      url.searchParams.set("order", "market_cap_desc");
      url.searchParams.set("per_page", perPage.toString());
      url.searchParams.set("page", page.toString());
      url.searchParams.set("sparkline", sparkline.toString());
      url.searchParams.set("price_change_percentage", "1h,24h,7d");
      
      const response = await fetchCoinGeckoTracked(
        url.toString(),
        "getCoinGeckoMarkets",
        "coins_markets"
      );
      
      if (!response.ok) {
        if (response.status === 429 || response.status === 401) {
          // Log rate limit / auth failure
          await logAuditEvent("external_rate_limit", request, { api: "coingecko", endpoint: "markets", status: response.status }, "warning");
          
          // Return cached data if available (even if stale)
          if (cached.exists) {
            console.log(`[getCoinGeckoMarkets] HTTP ${response.status} — returning stale cache`);
            return {
              coins: cached.data()?.coins || [],
              cached: true,
              stale: true,
              updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
            };
          }
          throw new HttpsError("resource-exhausted", `CoinGecko API error: ${response.status}`);
        }
        throw new HttpsError("internal", `CoinGecko API error: ${response.status}`);
      }
    
      const coins = await response.json();
      
      // Cache the result
      await cacheRef.set({
        coins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        coins,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      // SCALABILITY FIX: Always release the fetch lock
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getCoinGeckoMarkets");
  }
});

/**
 * Proxy CoinGecko global API with caching
 * 
 * Security: Rate limited
 */
export const getCoinGeckoGlobal = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    const cacheKey = "coingecko_global";
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.coinGeckoGlobal)) {
        return {
          global: data.global,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // SCALABILITY FIX: Request coalescing - only one request fetches from API
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache to be populated
      console.log(`[getCoinGeckoGlobal] Waiting for another request to complete fetch`);
      const { data, timedOut } = await waitForCachedData(cacheRef, CACHE_DURATIONS.coinGeckoGlobal);
      
      if (data && !timedOut) {
        return {
          global: data.global,
          cached: true,
          coalesced: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // RATE LIMIT FIX: Try Firestore globalStats first
    const firestoreGlobal = await db.collection("marketData").doc("globalStats").get();
    if (firestoreGlobal.exists) {
      const gsData = firestoreGlobal.data();
      const syncedAt = gsData?.updatedAt?.toDate?.() || new Date(gsData?.syncedAt || 0);
      const ageMs = Date.now() - syncedAt.getTime();
      
      if (ageMs < 10 * 60 * 1000 && gsData) {
        console.log(`[getCoinGeckoGlobal] Using Firestore global stats (${Math.round(ageMs / 1000)}s old)`);
        const globalObj = {
          data: {
            total_market_cap: { usd: gsData.totalMarketCap || 0 },
            total_volume: { usd: gsData.totalVolume24h || 0 },
            market_cap_percentage: {
              btc: gsData.btcDominance || 0,
              eth: gsData.ethDominance || 0,
            },
            market_cap_change_percentage_24h_usd: gsData.marketCapChange24h || 0,
            active_cryptocurrencies: gsData.activeCryptocurrencies || 0,
          },
        };
        
        await cacheRef.set({
          global: globalObj,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        if (acquiredLock) await releaseFetchLock(cacheKey);
        
        return {
          global: globalObj,
          cached: true,
          firestoreSource: true,
          updatedAt: gsData.updatedAt?.toDate?.()?.toISOString() || gsData.syncedAt,
        };
      }
    }
    
    // Cache miss - fetch from CoinGecko (tracked)
    try {
      const response = await fetchCoinGeckoTracked(
        "https://api.coingecko.com/api/v3/global",
        "getCoinGeckoGlobal",
        "global"
      );
      
      if (!response.ok) {
        if (response.status === 429 || response.status === 401) {
          // Log rate limit / auth failure
          await logAuditEvent("external_rate_limit", request, { api: "coingecko", endpoint: "global", status: response.status }, "warning");
          
          // Return cached data if available (even if stale)
          if (cached.exists) {
            console.log(`[getCoinGeckoGlobal] HTTP ${response.status} — returning stale cache`);
            return {
              global: cached.data()?.global || {},
              cached: true,
              stale: true,
              updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
            };
          }
          throw new HttpsError("resource-exhausted", `CoinGecko API error: ${response.status}`);
        }
        throw new HttpsError("internal", `CoinGecko API error: ${response.status}`);
      }
      
      const data = await response.json();
      
      // Cache the result
      await cacheRef.set({
        global: data.data,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        global: data.data,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getCoinGeckoGlobal");
  }
});

/**
 * Proxy Binance 24hr tickers API with caching
 * Provides real-time price data shared across all users
 * Cache TTL: 30 seconds (balances freshness with rate limit protection)
 * 
 * Security: Rate limited
 */
export const getBinance24hrTickers = onCall({
  timeoutSeconds: 15,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Input validation - optional symbols array
    const symbols = request.data?.symbols as string[] | undefined;
    
    // Build cache key based on requested symbols
    const symbolKey = symbols && symbols.length > 0 ? symbols.sort().join(",") : "all";
    const cacheKey = `binance_tickers_${symbolKey}`;
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, CACHE_DURATIONS.binanceTickers)) {
        return {
          tickers: data.tickers,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // SCALABILITY FIX: Request coalescing - only one request fetches from API
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache to be populated
      console.log(`[getBinance24hrTickers] Waiting for another request to complete fetch for ${cacheKey}`);
      const { data, timedOut } = await waitForCachedData(cacheRef, CACHE_DURATIONS.binanceTickers, 5000); // 5s max wait for Binance
      
      if (data && !timedOut) {
        return {
          tickers: data.tickers,
          cached: true,
          coalesced: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // Cache miss - fetch from Binance with fallback to Binance US
    try {
      // STRATEGY: Try Binance US first (since Binance.com is often geo-blocked from US servers),
      // then fall back to Binance.com if US fails
      const endpoints = [
        { base: "https://api.binance.us", suffix: "USD", name: "Binance US" },
        { base: "https://api.binance.com", suffix: "USDT", name: "Binance Global" },
      ];
      
      let tickers: any[] = [];
      let lastErrorMsg = "";
      
      for (const endpoint of endpoints) {
        try {
          // Always fetch all tickers first - more reliable and we filter client-side
          // Specific symbol requests often fail due to format differences between exchanges
          const url = `${endpoint.base}/api/v3/ticker/24hr`;
          
          console.log(`[getBinance24hrTickers] Trying ${endpoint.name}: ${url}`);
          
          const response = await fetch(url, {
            headers: {
              "Accept": "application/json",
              "User-Agent": "CryptoSage-Firebase/1.0",
            },
          });
          
          console.log(`[getBinance24hrTickers] ${endpoint.name} returned status ${response.status}`);
          
          if (response.status === 451) {
            // Geo-blocked - try next endpoint
            lastErrorMsg = `${endpoint.name}: geo-blocked (451)`;
            console.log(`[getBinance24hrTickers] ${lastErrorMsg}`);
            continue;
          }
          
          if (response.status === 429) {
            // Rate limited - log and return cached if available
            lastErrorMsg = `${endpoint.name}: rate limited (429)`;
            await logAuditEvent("external_rate_limit", request, { api: "binance", endpoint: "ticker/24hr" }, "warning");
            
            if (cached.exists) {
              return {
                tickers: cached.data()?.tickers || [],
                cached: true,
                stale: true,
                updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
              };
            }
            continue; // Try next endpoint instead of throwing
          }
          
          if (!response.ok) {
            const errorBody = await response.text().catch(() => "");
            lastErrorMsg = `${endpoint.name}: HTTP ${response.status} - ${errorBody.substring(0, 100)}`;
            console.log(`[getBinance24hrTickers] ${lastErrorMsg}`);
            continue;
          }
          
          const allTickers = await response.json();
          
          // Filter to requested symbols if specified, otherwise return all USD/USDT pairs
          if (symbols && symbols.length > 0) {
            // Normalize requested symbols and match against tickers
            const requestedBases = new Set(symbols.map(s => 
              s.toUpperCase().replace(/USDT$|USD$|BTC$/, "")
            ));
            
            tickers = allTickers.filter((t: { symbol: string }) => {
              const tickerBase = t.symbol.replace(/USDT$|USD$|BUSD$|USDC$/, "");
              return requestedBases.has(tickerBase);
            });
          } else {
            // Filter to USD/USDT pairs only for cleaner data
            tickers = allTickers.filter((t: { symbol: string }) => 
              (t.symbol.endsWith("USDT") || t.symbol.endsWith("USD")) && 
              !t.symbol.includes("UP") && !t.symbol.includes("DOWN") &&
              !t.symbol.includes("BULL") && !t.symbol.includes("BEAR")
            );
          }
          
          console.log(`[getBinance24hrTickers] Successfully fetched ${tickers.length} tickers from ${endpoint.name}`);
          break; // Success - exit the loop
          
        } catch (fetchError) {
          const err = fetchError as Error;
          lastErrorMsg = `${endpoint.name}: ${err.message}`;
          console.log(`[getBinance24hrTickers] ${lastErrorMsg}`);
          continue; // Try next endpoint
        }
      }
      
      // If no tickers fetched, return stale cache or throw error
      if (!tickers || tickers.length === 0) {
        if (cached.exists && cached.data()?.tickers?.length > 0) {
          // Return stale cache as fallback
          console.log(`[getBinance24hrTickers] All endpoints failed, returning stale cache with ${cached.data()?.tickers?.length} tickers`);
          return {
            tickers: cached.data()?.tickers || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("internal", `All Binance endpoints failed: ${lastErrorMsg}`);
      }
      
      // Cache the result
      await cacheRef.set({
        tickers: tickers,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        tickers: tickers,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getBinance24hrTickers");
  }
});

// ============================================================================
// COMMODITY PRICES
// ============================================================================

/**
 * Get commodity prices from Yahoo Finance with caching
 * Provides shared commodity price data across all users
 * Cache TTL: 60 seconds (commodities are less volatile than crypto)
 * 
 * Security: Rate limited
 */
export const getCommodityPrices = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Yahoo Finance commodity futures symbols
    const defaultSymbols = [
      // Precious Metals (4)
      "GC=F",   // Gold
      "SI=F",   // Silver
      "PL=F",   // Platinum
      "PA=F",   // Palladium
      // Industrial Metals (2)
      "HG=F",   // Copper
      "ALI=F",  // Aluminum
      // Energy (5)
      "CL=F",   // Crude Oil WTI
      "BZ=F",   // Brent Crude
      "NG=F",   // Natural Gas
      "HO=F",   // Heating Oil
      "RB=F",   // Gasoline
      // Agriculture (10)
      "ZC=F",   // Corn
      "ZS=F",   // Soybeans
      "ZW=F",   // Wheat
      "KC=F",   // Coffee
      "CC=F",   // Cocoa
      "CT=F",   // Cotton
      "SB=F",   // Sugar
      "ZO=F",   // Oats
      "ZR=F",   // Rough Rice
      "OJ=F",   // Orange Juice
      "LBS=F",  // Lumber
      // Livestock (3)
      "LE=F",   // Live Cattle
      "HE=F",   // Lean Hogs
      "GF=F",   // Feeder Cattle
    ];
    
    // Allow optional custom symbols
    const requestedSymbols = request.data?.symbols as string[] | undefined;
    const symbols = requestedSymbols && requestedSymbols.length > 0 
      ? requestedSymbols 
      : defaultSymbols;
    
    const symbolKey = symbols.sort().join(",");
    const cacheKey = `commodity_prices_${symbolKey.substring(0, 50)}`;
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);
    
    // Check cache first (60 second TTL for commodities)
    const COMMODITY_CACHE_TTL = 60 * 1000; // 60 seconds
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, COMMODITY_CACHE_TTL)) {
        return {
          prices: data.prices,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // Request coalescing - only one request fetches from API
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache
      console.log(`[getCommodityPrices] Waiting for another request to complete fetch`);
      const { data, timedOut } = await waitForCachedData(cacheRef, COMMODITY_CACHE_TTL, 10000);
      
      if (data && !timedOut) {
        return {
          prices: data.prices,
          cached: true,
          coalesced: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    try {
      // STRATEGY: Two-phase fetch for maximum coverage
      // Phase 1: v7/finance/quote batch endpoint (gets most symbols in one request)
      // Phase 2: v8/chart fallback for any symbols that failed in phase 1
      
      console.log(`[getCommodityPrices] Fetching ${symbols.length} commodity prices`);
      
      let prices: Array<{
        symbol: string;
        name: string;
        price: number;
        changePercent: number | null;
        previousClose: number | null;
        open: number | null;
        high: number | null;
        low: number | null;
        volume: number | null;
      }> = [];
      const successfulSymbols = new Set<string>();
      
      // ---- Phase 1: Batch fetch via v7/finance/quote (most efficient) ----
      // This endpoint returns data even when markets are closed
      try {
        const batchUrl = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${encodeURIComponent(symbols.join(","))}`;
        
        const batchResponse = await fetch(batchUrl, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Origin": "https://finance.yahoo.com",
            "Referer": "https://finance.yahoo.com/",
          },
        });
        
        if (batchResponse.ok) {
          const batchData = await batchResponse.json();
          const quoteResults = batchData?.quoteResponse?.result || [];
          
          console.log(`[getCommodityPrices] v7/quote returned ${quoteResults.length} results`);
          
          for (const q of quoteResults) {
            const price = q.regularMarketPrice;
            if (!price || price <= 0) continue;
            
            const prevClose = q.regularMarketPreviousClose;
            const changePercent = q.regularMarketChangePercent != null 
              ? q.regularMarketChangePercent 
              : (prevClose && prevClose > 0 ? ((price - prevClose) / prevClose) * 100 : null);
            
            prices.push({
              symbol: q.symbol,
              name: q.shortName || q.longName || q.symbol.replace("=F", " Futures"),
              price,
              changePercent,
              previousClose: prevClose || null,
              open: q.regularMarketOpen || null,
              high: q.regularMarketDayHigh || null,
              low: q.regularMarketDayLow || null,
              volume: q.regularMarketVolume || null,
            });
            successfulSymbols.add(q.symbol);
          }
        } else {
          console.log(`[getCommodityPrices] v7/quote batch failed: HTTP ${batchResponse.status}`);
        }
      } catch (err) {
        console.log(`[getCommodityPrices] v7/quote batch error: ${(err as Error).message}`);
      }
      
      // ---- Phase 2: Chart API fallback for any symbols that failed ----
      const failedSymbols = symbols.filter(s => !successfulSymbols.has(s));
      
      if (failedSymbols.length > 0) {
        console.log(`[getCommodityPrices] Phase 2: Fetching ${failedSymbols.length} remaining symbols via chart API`);
        
        const chartPromises = failedSymbols.map(async (symbol) => {
          // Use range=5d for better coverage (weekends, holidays)
          const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1d&range=5d`;
          
          try {
            const response = await fetch(url, {
              headers: {
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
              },
            });
            
            if (!response.ok) {
              console.log(`[getCommodityPrices] chart ${symbol}: HTTP ${response.status}`);
              return null;
            }
            
            const data = await response.json();
            const result = data.chart?.result?.[0];
            if (!result) return null;
            
            const meta = result.meta || {};
            const quote = result.indicators?.quote?.[0] || {};
            const closes = quote.close || [];
            
            // Get price from meta (most reliable) or last non-null close
            let currentPrice = meta.regularMarketPrice;
            if (!currentPrice && closes.length > 0) {
              for (let i = closes.length - 1; i >= 0; i--) {
                if (closes[i] != null) { currentPrice = closes[i]; break; }
              }
            }
            
            if (!currentPrice || currentPrice <= 0) return null;
            
            const previousClose = meta.previousClose || meta.chartPreviousClose;
            const changePercent = previousClose && previousClose > 0
              ? ((currentPrice - previousClose) / previousClose) * 100
              : null;
            
            return {
              symbol,
              name: meta.shortName || meta.longName || symbol.replace("=F", " Futures"),
              price: currentPrice,
              changePercent,
              previousClose: previousClose || null,
              open: meta.regularMarketOpen || null,
              high: meta.regularMarketDayHigh || null,
              low: meta.regularMarketDayLow || null,
              volume: meta.regularMarketVolume || null,
            };
          } catch (err) {
            console.log(`[getCommodityPrices] chart ${symbol} error: ${(err as Error).message}`);
            return null;
          }
        });
        
        const chartResults = await Promise.all(chartPromises);
        for (const result of chartResults) {
          if (result && result.price > 0) {
            prices.push(result);
            successfulSymbols.add(result.symbol);
          }
        }
      }
      
      const stillFailed = symbols.filter(s => !successfulSymbols.has(s));
      if (stillFailed.length > 0) {
        console.log(`[getCommodityPrices] ${stillFailed.length} symbols still failed: ${stillFailed.join(", ")}`);
      }
      
      // If no results, return stale cache or error
      if (prices.length === 0) {
        if (cached.exists && cached.data()?.prices?.length > 0) {
          console.log(`[getCommodityPrices] All fetches failed - returning stale cache`);
          return {
            prices: cached.data()?.prices || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("internal", "Failed to fetch commodity prices");
      }
      
      console.log(`[getCommodityPrices] Successfully fetched ${prices.length}/${symbols.length} commodity prices`);
      
      // Cache the result
      await cacheRef.set({
        prices,
        symbols,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        prices,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
      
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getCommodityPrices");
  }
});

// ============================================================================
// STOCK QUOTES (Yahoo Finance via Firebase proxy)
// ============================================================================

/**
 * Get stock quotes from Yahoo Finance with caching
 * Provides shared stock price data across all users, avoiding client-side rate limits
 * Cache TTL: 30 seconds (stocks are more volatile during market hours)
 * 
 * Security: Rate limited
 */
export const getStockQuotes = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Validate input - symbols are required for stocks
    const requestedSymbols = request.data?.symbols as string[] | undefined;
    if (!requestedSymbols || requestedSymbols.length === 0) {
      throw new HttpsError("invalid-argument", "symbols array is required");
    }
    
    // Limit batch size to prevent abuse
    const symbols = requestedSymbols.slice(0, 50);
    
    const symbolKey = symbols.sort().join(",");
    const cacheKey = `stock_quotes_${symbolKey.substring(0, 80)}`;
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);
    
    // Check cache first (30 second TTL for stocks)
    const STOCK_CACHE_TTL = 30 * 1000; // 30 seconds
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, STOCK_CACHE_TTL)) {
        return {
          quotes: data.quotes,
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    // Request coalescing - only one request fetches from API
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache
      console.log(`[getStockQuotes] Waiting for another request to complete fetch`);
      const { data, timedOut } = await waitForCachedData(cacheRef, STOCK_CACHE_TTL, 10000);
      
      if (data && !timedOut) {
        return {
          quotes: data.quotes,
          cached: true,
          coalesced: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }
    
    try {
      // STRATEGY: Two-phase fetch for maximum coverage
      // Phase 1: v7/finance/quote batch endpoint (most symbols in one request)
      // Phase 2: v8/chart fallback for any symbols that failed
      
      console.log(`[getStockQuotes] Fetching ${symbols.length} stock quotes`);
      
      const quotes: Array<{
        symbol: string; name: string; price: number;
        change: number | null; changePercent: number | null;
        previousClose: number | null; open: number | null;
        high: number | null; low: number | null;
        volume: number | null; marketCap: number | null;
        quoteType: string | null; exchange: string | null;
        currency: string | null;
      }> = [];
      const successfulSymbols = new Set<string>();
      
      // ---- Phase 1: Batch fetch via v7/finance/quote ----
      try {
        const batchUrl = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${encodeURIComponent(symbols.join(","))}`;
        
        const batchResponse = await fetch(batchUrl, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Origin": "https://finance.yahoo.com",
            "Referer": "https://finance.yahoo.com/",
          },
        });
        
        if (batchResponse.ok) {
          const batchData = await batchResponse.json();
          const quoteResults = batchData?.quoteResponse?.result || [];
          
          console.log(`[getStockQuotes] v7/quote returned ${quoteResults.length} results`);
          
          for (const q of quoteResults) {
            const price = q.regularMarketPrice;
            if (!price || price <= 0) continue;
            
            const prevClose = q.regularMarketPreviousClose;
            const changeVal = q.regularMarketChange ?? (prevClose ? price - prevClose : null);
            const changePct = q.regularMarketChangePercent ?? (prevClose && prevClose > 0 ? ((price - prevClose) / prevClose) * 100 : null);
            
            quotes.push({
              symbol: q.symbol,
              name: q.shortName || q.longName || q.symbol,
              price,
              change: changeVal,
              changePercent: changePct,
              previousClose: prevClose || null,
              open: q.regularMarketOpen || null,
              high: q.regularMarketDayHigh || null,
              low: q.regularMarketDayLow || null,
              volume: q.regularMarketVolume || null,
              marketCap: q.marketCap || null,
              quoteType: q.quoteType || null,
              exchange: q.exchange || null,
              currency: q.currency || null,
            });
            successfulSymbols.add(q.symbol);
          }
        } else {
          console.log(`[getStockQuotes] v7/quote batch failed: HTTP ${batchResponse.status}`);
        }
      } catch (err) {
        console.log(`[getStockQuotes] v7/quote batch error: ${(err as Error).message}`);
      }
      
      // ---- Phase 2: Chart API fallback for failed symbols ----
      const failedSymbols = symbols.filter(s => !successfulSymbols.has(s));
      
      if (failedSymbols.length > 0) {
        console.log(`[getStockQuotes] Phase 2: Fetching ${failedSymbols.length} remaining via chart API`);
        
        const chartPromises = failedSymbols.map(async (symbol) => {
          const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?interval=1d&range=5d`;
          try {
            const response = await fetch(url, {
              headers: {
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
              },
            });
            if (!response.ok) return null;
            const data = await response.json();
            const result = data.chart?.result?.[0];
            if (!result) return null;
            const meta = result.meta || {};
            const ind = result.indicators?.quote?.[0] || {};
            const closes = ind.close || [];
            let currentPrice = meta.regularMarketPrice;
            if (!currentPrice && closes.length > 0) {
              for (let i = closes.length - 1; i >= 0; i--) {
                if (closes[i] != null) { currentPrice = closes[i]; break; }
              }
            }
            if (!currentPrice || currentPrice <= 0) return null;
            const previousClose = meta.previousClose || meta.chartPreviousClose;
            return {
              symbol, name: meta.shortName || meta.longName || symbol, price: currentPrice,
              change: previousClose ? currentPrice - previousClose : null,
              changePercent: previousClose && previousClose > 0 ? ((currentPrice - previousClose) / previousClose) * 100 : null,
              previousClose: previousClose || null, open: meta.regularMarketOpen || null,
              high: meta.regularMarketDayHigh || null, low: meta.regularMarketDayLow || null,
              volume: meta.regularMarketVolume || null, marketCap: meta.marketCap || null,
              quoteType: meta.instrumentType || meta.quoteType || null,
              exchange: meta.exchangeName || null, currency: meta.currency || null,
            };
          } catch { return null; }
        });
        
        const chartResults = await Promise.all(chartPromises);
        for (const result of chartResults) {
          if (result && result.price > 0) {
            quotes.push(result);
            successfulSymbols.add(result.symbol);
          }
        }
      }
      
      // If no results, return stale cache or error
      if (quotes.length === 0) {
        if (cached.exists && cached.data()?.quotes?.length > 0) {
          console.log(`[getStockQuotes] All fetches failed - returning stale cache`);
          return {
            quotes: cached.data()?.quotes || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("internal", "Failed to fetch stock quotes");
      }
      
      console.log(`[getStockQuotes] Successfully fetched ${quotes.length}/${symbols.length} stock quotes`);
      
      // Cache the result
      await cacheRef.set({
        quotes,
        symbols,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        quotes,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
      
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getStockQuotes");
  }
});

/**
 * Get stock sparkline history from Yahoo Finance chart API with caching
 * Provides shared historical close series across all users.
 * Cache TTL: 60 seconds
 *
 * Security: Rate limited
 */
export const getStockSparklines = onCall({
  timeoutSeconds: 60,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);

  try {
    await checkRateLimit(clientIP, "publicMarket");

    const requestedSymbols = request.data?.symbols as string[] | undefined;
    if (!requestedSymbols || requestedSymbols.length === 0) {
      throw new HttpsError("invalid-argument", "symbols array is required");
    }

    const rangeInput = (request.data?.range as string | undefined) ?? "1d";
    const intervalInput = (request.data?.interval as string | undefined) ?? "5m";
    const allowedRanges = new Set(["1d", "5d", "1mo"]);
    const allowedIntervals = new Set(["1m", "5m", "15m", "30m", "60m", "1d"]);
    const range = allowedRanges.has(rangeInput) ? rangeInput : "1d";
    const interval = allowedIntervals.has(intervalInput) ? intervalInput : "5m";

    // Normalize and cap symbol count to prevent abuse.
    const symbols = [...new Set(requestedSymbols.map((s) => String(s || "").trim().toUpperCase()).filter(Boolean))].slice(0, 50);
    if (symbols.length === 0) {
      throw new HttpsError("invalid-argument", "no valid symbols provided");
    }

    const symbolKey = symbols.slice().sort().join(",");
    const cacheKey = `stock_sparklines_${range}_${interval}_${symbolKey.substring(0, 80)}`;
    const cacheRef = db.collection("marketDataCache").doc(cacheKey);

    // Check cache first.
    const STOCK_SPARKLINE_TTL = 60 * 1000;
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, STOCK_SPARKLINE_TTL)) {
        return {
          sparklines: data.sparklines || [],
          cached: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }

    // Request coalescing.
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    if (!acquiredLock) {
      console.log("[getStockSparklines] Waiting for another request to complete fetch");
      const { data, timedOut } = await waitForCachedData(cacheRef, STOCK_SPARKLINE_TTL, 12000);
      if (data && !timedOut) {
        return {
          sparklines: data.sparklines || [],
          cached: true,
          coalesced: true,
          updatedAt: data.updatedAt.toDate().toISOString(),
        };
      }
    }

    try {
      console.log(`[getStockSparklines] Fetching ${symbols.length} sparklines (range=${range}, interval=${interval})`);

      const FETCH_TIMEOUT_MS = 8000;
      const MAX_CONCURRENCY = 8;
      const yahooChartHosts = [
        "https://query1.finance.yahoo.com",
        "https://query2.finance.yahoo.com",
      ];

      const fetchSymbolSparkline = async (symbol: string): Promise<{ symbol: string; prices: number[] } | null> => {
        for (const host of yahooChartHosts) {
          const url = `${host}/v8/finance/chart/${encodeURIComponent(symbol)}?range=${encodeURIComponent(range)}&interval=${encodeURIComponent(interval)}&includePrePost=false`;
          const controller = new AbortController();
          const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
          try {
            const response = await fetch(url, {
              headers: {
                "Accept": "application/json",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
              },
              signal: controller.signal,
            });
            if (!response.ok) {
              continue;
            }

            const payload = await response.json();
            const result = payload?.chart?.result?.[0];
            const closeSeries = result?.indicators?.quote?.[0]?.close;
            if (!Array.isArray(closeSeries)) {
              continue;
            }

            const prices = closeSeries
              .filter((v: unknown) => typeof v === "number" && Number.isFinite(v) && v > 0)
              .map((v: number) => Number(v));
            if (prices.length < 10) {
              continue;
            }

            return { symbol, prices };
          } catch (err) {
            const message = (err as Error).message || "unknown";
            console.log(`[getStockSparklines] chart ${symbol} via ${host} error: ${message}`);
          } finally {
            clearTimeout(timeout);
          }
        }
        return null;
      };

      // Bounded concurrency to prevent long-tail stalls and outbound spikes.
      const sparklineResults: Array<{ symbol: string; prices: number[] } | null> = [];
      for (let i = 0; i < symbols.length; i += MAX_CONCURRENCY) {
        const chunk = symbols.slice(i, i + MAX_CONCURRENCY);
        const chunkResults = await Promise.all(chunk.map(fetchSymbolSparkline));
        sparklineResults.push(...chunkResults);
      }

      const sparklines = sparklineResults.filter((entry): entry is { symbol: string; prices: number[] } => Boolean(entry));

      if (sparklines.length === 0) {
        if (cached.exists && cached.data()?.sparklines?.length > 0) {
          console.log("[getStockSparklines] All fetches failed - returning stale cache");
          return {
            sparklines: cached.data()?.sparklines || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("internal", "Failed to fetch stock sparklines");
      }

      await cacheRef.set({
        sparklines,
        symbols,
        range,
        interval,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        sparklines,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getStockSparklines");
  }
});

// ============================================================================
// PUMP.FUN MEME COIN DATA
// ============================================================================

/**
 * Get trending meme coins from Pump.fun (Solana meme coin launchpad)
 * Proxied through Firebase to avoid geo-blocking and rate limits
 * Cache TTL: 2 minutes (meme coins are volatile)
 * 
 * Returns recently launched and trending tokens for market tracking
 */
export const getPumpFunTokens = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
  maxInstances: 10,
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    const { type = "recent" } = request.data || {};
    
    // Validate type
    const validTypes = ["recent", "trending", "graduated"];
    if (!validTypes.includes(type)) {
      throw new HttpsError("invalid-argument", `Invalid type. Must be one of: ${validTypes.join(", ")}`);
    }
    
    const cacheKey = `pumpfun_${type}`;
    const cacheRef = db.collection("pumpfunCache").doc(cacheKey);
    const cacheDuration = 2 * 60 * 1000; // 2 minutes
    
    // Check cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, cacheDuration)) {
        console.log(`[getPumpFunTokens] Cache HIT for ${type} (${data.tokens?.length || 0} tokens)`);
        return {
          tokens: data.tokens || [],
          type,
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
        };
      }
    }
    
    // Cache miss - fetch from Pump.fun
    console.log(`[getPumpFunTokens] Cache MISS for ${type}, fetching from API...`);
    
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    if (!acquiredLock) {
      // Another request is fetching, wait for cache
      console.log(`[getPumpFunTokens] Waiting for another request to fetch ${type}`);
      const { data, timedOut } = await waitForCachedData(cacheRef, cacheDuration, 10000);
      if (data && !timedOut) {
        return {
          tokens: data.tokens || [],
          type,
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
        };
      }
    }
    
    try {
      // Determine sort parameters based on type
      let sortBy = "created_timestamp";
      let order = "DESC";
      
      if (type === "trending") {
        sortBy = "market_cap";
        order = "DESC";
      } else if (type === "graduated") {
        sortBy = "market_cap";
        order = "DESC";
      }
      
      // Fetch from Pump.fun API
      const pumpfunUrl = `https://frontend-api.pump.fun/coins?offset=0&limit=50&sort=${sortBy}&order=${order}&includeNsfw=false`;
      
      console.log(`[getPumpFunTokens] Fetching from: ${pumpfunUrl}`);
      
      const response = await fetch(pumpfunUrl, {
        headers: {
          "Accept": "application/json",
          "User-Agent": "CryptoSage-Firebase/1.0",
        },
      });
      
      if (!response.ok) {
        console.log(`[getPumpFunTokens] Pump.fun API error ${response.status}, trying CoinGecko meme category...`);
        
        // Fallback to CoinGecko meme-token category
        try {
          const cgUrl = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&category=meme-token&order=market_cap_desc&per_page=50&page=1&sparkline=false";
          await trackCoinGeckoCall("getPumpFunTokens", "coins_markets_meme");
          const cgResponse = await fetch(cgUrl, {
            headers: getCoinGeckoHeaders(),
          });
          
          if (cgResponse.ok) {
            const cgCoins = await cgResponse.json();
            const memeTokens = cgCoins.map((coin: { id: string; symbol: string; name: string; image?: string; current_price?: number; market_cap?: number; price_change_percentage_24h?: number }) => ({
              mint: coin.id,
              name: coin.name,
              symbol: coin.symbol.toUpperCase(),
              description: `Top meme coin by market cap`,
              imageUri: coin.image || null,
              createdTimestamp: Date.now(),
              marketCapSol: null,
              usdMarketCap: coin.market_cap || null,
              replyCount: 0,
              lastReply: null,
              creator: null,
              raydiumPool: null,
              complete: true,
              isGraduated: true,
              // Extra fields for CoinGecko data
              currentPrice: coin.current_price || null,
              priceChange24h: coin.price_change_percentage_24h || null,
              source: "coingecko",
            }));
            
            console.log(`[getPumpFunTokens] CoinGecko fallback: ${memeTokens.length} meme coins`);
            
            // Cache the result
            await cacheRef.set({
              tokens: memeTokens,
              type,
              source: "coingecko",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            
            return {
              tokens: memeTokens,
              type,
              cached: false,
              source: "coingecko",
              updatedAt: new Date().toISOString(),
            };
          }
        } catch (cgError) {
          console.log(`[getPumpFunTokens] CoinGecko fallback also failed: ${(cgError as Error).message}`);
        }
        
        // Return stale cache if available
        if (cached.exists && cached.data()?.tokens?.length > 0) {
          console.log(`[getPumpFunTokens] All APIs failed, returning stale cache`);
          return {
            tokens: cached.data()?.tokens || [],
            type,
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("internal", `All meme coin APIs failed (Pump.fun: ${response.status})`);
      }
      
      const rawData = await response.json();
      
      // Parse tokens - handle both array and wrapped response
      let tokens: Array<{
        mint: string;
        name: string;
        symbol: string;
        description?: string;
        image_uri?: string;
        created_timestamp: number;
        market_cap_sol?: number;
        usd_market_cap?: number;
        reply_count?: number;
        last_reply?: number;
        creator?: string;
        raydium_pool?: string;
        complete?: boolean;
      }> = [];
      
      if (Array.isArray(rawData)) {
        tokens = rawData;
      } else if (rawData.coins && Array.isArray(rawData.coins)) {
        tokens = rawData.coins;
      }
      
      // Filter tokens with minimum liquidity (10 SOL market cap)
      const minMarketCapSol = 10;
      const filteredTokens = tokens
        .filter(t => (t.market_cap_sol || 0) >= minMarketCapSol)
        .map(t => ({
          mint: t.mint,
          name: t.name,
          symbol: t.symbol,
          description: t.description || null,
          imageUri: t.image_uri || null,
          createdTimestamp: t.created_timestamp,
          marketCapSol: t.market_cap_sol || null,
          usdMarketCap: t.usd_market_cap || null,
          replyCount: t.reply_count || 0,
          lastReply: t.last_reply || null,
          creator: t.creator || null,
          raydiumPool: t.raydium_pool || null,
          complete: t.complete || false,
          isGraduated: !!(t.raydium_pool || t.complete),
        }));
      
      // For graduated type, filter only graduated tokens
      const finalTokens = type === "graduated" 
        ? filteredTokens.filter(t => t.isGraduated)
        : filteredTokens;
      
      console.log(`[getPumpFunTokens] Fetched ${finalTokens.length} ${type} tokens`);
      
      // Cache the result
      await cacheRef.set({
        tokens: finalTokens,
        type,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        tokens: finalTokens,
        type,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
      
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getPumpFunTokens");
  }
});

// ============================================================================
// SCHEDULED FUNCTIONS
// ============================================================================

/**
 * Pre-warm market sentiment cache every hour
 * This ensures users always get fast responses
 */
export const prewarmMarketSentiment = onSchedule({
  schedule: "every 60 minutes",
  timeZone: "UTC",
  memory: "256MiB",
}, async () => {
  console.log("Pre-warming market sentiment cache...");
  
  try {
    const openai = getOpenAIClient();
    
    const systemPrompt = `You are a professional cryptocurrency market analyst providing daily market sentiment analysis.`;
    const userPrompt = `Provide a brief market sentiment analysis for the cryptocurrency market. 2-3 sentences maximum.`;

    const completion = await openai.chat.completions.create({
      model: "gpt-4.1-mini", // Premium model for pre-warmed shared content
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 200,
      temperature: 0.7,
    });

    const content = completion.choices[0]?.message?.content || "";
    
    await db.collection("sharedAICache").doc("marketSentiment").set({
      content,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: "gpt-4.1-mini",
      tokens: completion.usage?.total_tokens || 0,
      prewarmed: true,
    });
    
    console.log("Market sentiment cache pre-warmed successfully");
  } catch (error) {
    console.error("Error pre-warming market sentiment:", error);
  }
});

/**
 * Pre-warm CryptoSage AI Sentiment cache every 3 minutes
 * This ensures all users see consistent, fresh sentiment scores
 * 
 * ENHANCED ALGORITHM v2.1 - Uses 10 factors for comprehensive market sentiment:
 * 1. Market Breadth (% of coins positive)
 * 2. BTC Momentum (1h, 24h, 7d)
 * 3. ETH as Leading Indicator
 * 4. Altcoin Performance
 * 5. Risk Tilt (small vs large cap, alts vs BTC)
 * 6. BTC Dominance (flight to safety)
 * 7. Momentum Consistency (timeframe alignment)
 * 8. Volume Confirmation
 * 9. Distance from ATH
 * 10. Google Trends (retail search sentiment - "bitcoin crash" vs "buy bitcoin")
 */
export const prewarmCryptoSageAISentiment = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "UTC",
  memory: "256MiB",
}, async () => {
  console.log("[prewarmCryptoSageAISentiment] Pre-warming CryptoSage AI sentiment cache (v2.1 - Firestore-first)...");
  
  try {
    // RATE LIMIT FIX: Read from Firestore instead of calling CoinGecko directly.
    // syncCoinGeckoToFirestore already fetches this data every 5 minutes and stores it.
    // This eliminates ~28,800 redundant CoinGecko calls per month.
    
    let coins: Array<{
      symbol: string;
      market_cap: number;
      market_cap_rank: number;
      total_volume?: number;
      price_change_percentage_1h_in_currency?: number;
      price_change_percentage_24h_in_currency?: number;
      price_change_percentage_7d_in_currency?: number;
      price_change_percentage_24h?: number;
      sparkline_in_7d?: { price: number[] };
      ath?: number;
      current_price?: number;
    }> = [];
    
    let btcDominance = 50;
    
    // Try Firestore first (zero CoinGecko API calls)
    const coingeckoDoc = await db.collection("marketData").doc("coingeckoMarkets").get();
    const globalDoc = await db.collection("marketData").doc("globalStats").get();
    
    if (coingeckoDoc.exists) {
      const data = coingeckoDoc.data();
      if (data?.coins && Array.isArray(data.coins) && data.coins.length > 0) {
        // Check freshness - Firestore data should be < 10 minutes old
        const syncedAt = data.updatedAt?.toDate?.() || new Date(data.syncedAt || 0);
        const ageMs = Date.now() - syncedAt.getTime();
        
        if (ageMs < 10 * 60 * 1000) { // < 10 minutes
          coins = data.coins;
          console.log(`[prewarmCryptoSageAISentiment] Using Firestore CoinGecko data (${coins.length} coins, ${Math.round(ageMs / 1000)}s old)`);
        } else {
          console.log(`[prewarmCryptoSageAISentiment] Firestore data is stale (${Math.round(ageMs / 60000)}m old), falling back to API`);
        }
      }
    }
    
    if (globalDoc.exists) {
      const globalData = globalDoc.data();
      btcDominance = globalData?.btcDominance ?? 50;
    }
    
    // Fallback: Only call CoinGecko API if Firestore data is unavailable or stale
    if (coins.length === 0) {
      console.log("[prewarmCryptoSageAISentiment] Firestore miss - fetching from CoinGecko API (fallback)...");
      
      const coinGeckoUrl = "https://api.coingecko.com/api/v3/coins/markets?" +
        "vs_currency=usd&order=market_cap_desc&per_page=100&page=1&sparkline=true&" +
        "price_change_percentage=1h,24h,7d";
      
      const coinsResponse = await fetchCoinGeckoTracked(
        coinGeckoUrl,
        "prewarmCryptoSageAISentiment",
        "coins_markets"
      );
      
      if (!coinsResponse.ok) {
        console.error(`[prewarmCryptoSageAISentiment] CoinGecko API error: ${coinsResponse.status}`);
        return;
      }
      
      coins = await coinsResponse.json();
      
      // Also fetch global as fallback
      if (btcDominance === 50) {
        try {
          const globalResponse = await fetchCoinGeckoTracked(
            "https://api.coingecko.com/api/v3/global",
            "prewarmCryptoSageAISentiment",
            "global"
          );
          if (globalResponse.ok) {
            const globalData = await globalResponse.json();
            btcDominance = globalData?.data?.market_cap_percentage?.btc ?? 50;
          }
        } catch { /* ignore */ }
      }
    }
    
    if (!Array.isArray(coins) || coins.length < 10) {
      console.error("[prewarmCryptoSageAISentiment] Insufficient market data");
      return;
    }
    
    const stablecoins = new Set(["USDT", "USDC", "BUSD", "DAI", "FDUSD", "TUSD", "USDP", "GUSD", "FRAX", "LUSD", "PYUSD"]);
    
    const effectiveCoins = coins
      .filter(c => c.market_cap > 0)
      .sort((a, b) => (a.market_cap_rank || 9999) - (b.market_cap_rank || 9999))
      .slice(0, 100);
    
    // Factor 1: Market Breadth
    const coinsWithChange = effectiveCoins.filter(c => {
      const change = c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h;
      return change !== undefined && change !== null && isFinite(change);
    });
    
    const upCoins = coinsWithChange.filter(c => {
      const change = c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h ?? 0;
      return change > 0;
    });
    
    const simpleBreadth = coinsWithChange.length > 0 ? upCoins.length / coinsWithChange.length : 0.5;
    const totalCap = coinsWithChange.reduce((sum, c) => sum + (c.market_cap || 0), 0);
    const upCap = upCoins.reduce((sum, c) => sum + (c.market_cap || 0), 0);
    const weightedBreadth = totalCap > 0 ? upCap / totalCap : 0.5;
    const breadthCombined = 0.6 * weightedBreadth + 0.4 * simpleBreadth;
    
    // Factor 2: BTC Momentum
    const btcCoin = effectiveCoins.find(c => c.symbol.toUpperCase() === "BTC");
    const btc24h = btcCoin?.price_change_percentage_24h_in_currency ?? btcCoin?.price_change_percentage_24h ?? 0;
    const btc1h = btcCoin?.price_change_percentage_1h_in_currency ?? 0;
    let btc7d = btcCoin?.price_change_percentage_7d_in_currency ?? 0;
    if (btc7d === 0 && btcCoin?.sparkline_in_7d?.price) {
      const prices = btcCoin.sparkline_in_7d.price;
      if (prices.length >= 2 && prices[0] > 0 && prices[prices.length - 1] > 0) {
        btc7d = ((prices[prices.length - 1] - prices[0]) / prices[0]) * 100;
      }
    }
    
    // Factor 3: ETH as Leading Indicator
    const ethCoin = effectiveCoins.find(c => c.symbol.toUpperCase() === "ETH");
    const eth24h = ethCoin?.price_change_percentage_24h_in_currency ?? ethCoin?.price_change_percentage_24h ?? 0;
    const ethVsBtc24h = eth24h - btc24h;
    
    // Factor 4: Altcoin Analysis
    const altcoins = effectiveCoins.filter(c => 
      c.symbol.toUpperCase() !== "BTC" && !stablecoins.has(c.symbol.toUpperCase())
    );
    const altChanges = altcoins
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && c !== null && isFinite(c));
    const altMedian = safeMedian(altChanges);
    const dispersion = 0.5 * stddev(altChanges) + 0.5 * mad(altChanges);
    
    // Factor 5: Risk Tilt
    const largeChanges = altcoins.slice(0, 50)
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && isFinite(c));
    const smallChanges = altcoins.slice(50, 100)
      .map(c => c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h)
      .filter((c): c is number => c !== undefined && isFinite(c));
    const smallVsLargeDelta = safeMedian(smallChanges) - safeMedian(largeChanges);
    const altsVsBTCDelta = altMedian - btc24h;
    
    // Factor 6: BTC Dominance
    const btcDomTerm = (btcDominance - 50) / 10;
    const btcDomContrib = -btcDomTerm * 4.0;
    
    // Factor 7: Momentum Consistency
    const btcMomentumAligned = (btc1h > 0 && btc24h > 0 && btc7d > 0) || (btc1h < 0 && btc24h < 0 && btc7d < 0);
    const momentumBonus = btcMomentumAligned ? (btc24h > 0 ? 3.0 : -3.0) : 0;
    
    // Factor 8: Volume Confirmation
    const volumeRatios = effectiveCoins
      .filter(c => c.total_volume && c.market_cap && c.market_cap > 0)
      .map(c => ({ ratio: (c.total_volume || 0) / c.market_cap, change: c.price_change_percentage_24h_in_currency ?? c.price_change_percentage_24h ?? 0 }));
    let volumeSentiment = 0;
    if (volumeRatios.length > 10) {
      const avgRatio = volumeRatios.reduce((s, v) => s + v.ratio, 0) / volumeRatios.length;
      const highVolumeCoins = volumeRatios.filter(v => v.ratio > avgRatio * 1.2);
      if (highVolumeCoins.length > 0) {
        const avgChange = highVolumeCoins.reduce((s, v) => s + v.change, 0) / highVolumeCoins.length;
        volumeSentiment = Math.tanh(avgChange / 5.0) * 3.0;
      }
    }
    
    // Factor 9: Distance from ATH
    const athDistances = effectiveCoins
      .filter(c => c.ath && c.current_price && c.ath > 0)
      .map(c => ((c.current_price || 0) / (c.ath || 1)) * 100);
    let athSentiment = 0;
    if (athDistances.length > 20) {
      const avgAthPct = athDistances.reduce((s, v) => s + v, 0) / athDistances.length;
      athSentiment = Math.tanh((avgAthPct - 50) / 25) * 3.0;
    }
    
    // Factor 10: Google Trends Sentiment
    let googleTrendsSentiment = 0;
    try {
      const trendsData = await fetchGoogleTrendsSentiment();
      if (trendsData) {
        googleTrendsSentiment = (trendsData.score - 50) / 10;
        console.log(`[prewarmCryptoSageAISentiment] Google Trends: score=${trendsData.score}, contrib=${googleTrendsSentiment.toFixed(1)}`);
      }
    } catch (e) {
      console.log("[prewarmCryptoSageAISentiment] Google Trends unavailable, skipping");
    }
    
    // Calculate final score
    const breadthTerm = (breadthCombined - 0.5) * 2.0;
    const disp = Math.max(0, Math.min(100, dispersion));
    const volFactor = Math.min(1.0, Math.tanh(disp / 20.0));
    const calmFactor = 1.0 - volFactor;
    
    // Weights
    const wBreadth = 12.0, wBTC24 = 10.0;
    const wBTC7 = 6.0 + 2.0 * calmFactor;
    const wBTC1h = 1.0 + 1.5 * calmFactor;
    const wAltMed = 4.0 + 2.0 * calmFactor;
    const wDispPenalty = 6.0 + 10.0 * volFactor;
    const wRiskSmallVsLarge = 2.0 + 1.0 * calmFactor;
    const wRiskAltsVsBTC = 2.0 + 1.0 * calmFactor;
    const wEthVsBtc = 2.0 + 1.0 * calmFactor;
    
    let scoreRaw = 50.0
      + wBTC24 * Math.tanh(clampPercent(btc24h) / 8.0)
      + wBreadth * breadthTerm
      + wBTC7 * Math.tanh(clampPercent(btc7d) / 15.0)
      + wBTC1h * Math.tanh(clampPercent(btc1h) / 3.0)
      + wAltMed * Math.tanh(clampPercent(altMedian) / 6.0)
      - wDispPenalty * Math.tanh(disp / 15.0)
      + wRiskSmallVsLarge * Math.tanh(smallVsLargeDelta / 3.0)
      + wRiskAltsVsBTC * Math.tanh(altsVsBTCDelta / 4.0)
      + wEthVsBtc * Math.tanh(ethVsBtc24h / 4.0)
      + btcDomContrib
      + momentumBonus
      + volumeSentiment
      + athSentiment
      + googleTrendsSentiment;
    
    // Guards
    const coverageRatio = coinsWithChange.length / effectiveCoins.length;
    if (coverageRatio < 0.3) scoreRaw = 50 + (scoreRaw - 50) * 0.5;
    if (scoreRaw < 15) scoreRaw = 10 + (scoreRaw - 10) * 0.5;
    if (scoreRaw > 85) scoreRaw = 90 - (90 - scoreRaw) * 0.5;
    
    const score = Math.round(Math.max(0, Math.min(100, scoreRaw)));
    const verdict = getVerdictFromScore(score);
    
    // Cache the result with enhanced metadata
    await db.collection("sharedAICache").doc("cryptoSageAISentiment").set({
      score,
      verdict,
      breadth: Math.round(breadthCombined * 100),
      btc24h: Math.round(btc24h * 100) / 100,
      btc7d: Math.round(btc7d * 100) / 100,
      altMedian: Math.round(altMedian * 100) / 100,
      volatility: Math.round(disp * 10) / 10,
      btcDominance: Math.round(btcDominance * 10) / 10,
      ethVsBtc: Math.round(ethVsBtc24h * 100) / 100,
      googleTrends: Math.round(googleTrendsSentiment * 10) / 10,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      prewarmed: true,
      algorithmVersion: "2.1",
    });
    
    // Store daily history
    const now = new Date();
    const todayKey = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}-${String(now.getUTCDate()).padStart(2, "0")}`;
    const historyRef = db.collection("sharedAICache").doc("cryptoSageAIHistory");
    const historyDoc = await historyRef.get();
    const historyData = historyDoc.exists ? historyDoc.data() || {} : {};
    const dailyScores: Record<string, { score: number; verdict: string; timestamp: string }> = historyData.dailyScores || {};
    
    if (!dailyScores[todayKey]) {
      dailyScores[todayKey] = { score, verdict, timestamp: now.toISOString() };
      const sortedKeys = Object.keys(dailyScores).sort().reverse();
      const trimmedScores: typeof dailyScores = {};
      for (const key of sortedKeys.slice(0, 35)) trimmedScores[key] = dailyScores[key];
      await historyRef.set({ dailyScores: trimmedScores, lastUpdated: admin.firestore.FieldValue.serverTimestamp() });
      console.log(`[prewarmCryptoSageAISentiment] Stored daily history for ${todayKey}: score=${score}`);
    }
    
    console.log(`[prewarmCryptoSageAISentiment] v2.1 Cache pre-warmed: score=${score} (${verdict}), ` +
      `breadth=${Math.round(breadthCombined * 100)}%, BTC=${btc24h.toFixed(1)}%, ETH-BTC=${ethVsBtc24h.toFixed(1)}%, ` +
      `BTCDom=${btcDominance.toFixed(1)}%, momentum=${btcMomentumAligned ? "aligned" : "mixed"}, ` +
      `gTrends=${googleTrendsSentiment.toFixed(1)}`);
  } catch (error) {
    console.error("[prewarmCryptoSageAISentiment] Error:", error);
  }
});

/**
 * Pre-warm top coin insights every 2 hours
 */
export const prewarmTopCoinInsights = onSchedule({
  schedule: "every 120 minutes",
  timeZone: "UTC",
  memory: "512MiB",
}, async () => {
  console.log("Pre-warming top coin insights...");
  
  const topCoins = [
    { id: "bitcoin", symbol: "BTC", name: "Bitcoin" },
    { id: "ethereum", symbol: "ETH", name: "Ethereum" },
    { id: "solana", symbol: "SOL", name: "Solana" },
    { id: "ripple", symbol: "XRP", name: "XRP" },
    { id: "cardano", symbol: "ADA", name: "Cardano" },
    { id: "dogecoin", symbol: "DOGE", name: "Dogecoin" },
    { id: "avalanche-2", symbol: "AVAX", name: "Avalanche" },
    { id: "chainlink", symbol: "LINK", name: "Chainlink" },
    { id: "polkadot", symbol: "DOT", name: "Polkadot" },
    { id: "polygon", symbol: "MATIC", name: "Polygon" },
  ];
  
  try {
    const openai = getOpenAIClient();
    
    for (const coin of topCoins) {
      try {
        const systemPrompt = `You are a cryptocurrency analyst providing brief coin insights. Be concise (2-3 sentences).`;
        const userPrompt = `Provide a brief analysis for ${coin.name} (${coin.symbol}). Focus on what traders should know.`;

        const completion = await openai.chat.completions.create({
          model: "gpt-4.1-mini", // Premium model for pre-warmed shared content
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
          max_tokens: 200,
          temperature: 0.7,
        });

        const content = completion.choices[0]?.message?.content || "";
        
        await db.collection("sharedAICache").doc(`coin_${coin.id}`).set({
          content,
          technicalSummary: null,
          coinId: coin.id,
          symbol: coin.symbol,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          model: "gpt-4.1-mini",
          prewarmed: true,
        });
        
        // Small delay to avoid rate limits
        await new Promise(resolve => setTimeout(resolve, 500));
      } catch (coinError) {
        console.error(`Error pre-warming ${coin.symbol}:`, coinError);
      }
    }
    
    console.log("Top coin insights pre-warmed successfully");
  } catch (error) {
    console.error("Error pre-warming coin insights:", error);
  }
});

// ============================================================================
// REAL-TIME MARKET DATA SYNC (Heat Map Consistency Fix)
// ============================================================================

/**
 * Top coins for which we calculate 1H changes from Binance klines
 * These are the most commonly watched coins that should have consistent 1H data
 */
const TOP_COINS_FOR_1H = [
  "BTC", "ETH", "SOL", "XRP", "BNB", "DOGE", "ADA", "AVAX", "LINK", "DOT",
  "MATIC", "SHIB", "LTC", "UNI", "ATOM", "XLM", "FIL", "NEAR", "APT", "ARB",
  "OP", "IMX", "INJ", "SUI", "SEI", "TIA", "JUP", "PEPE", "WIF", "BONK"
];

/**
 * Fetch 1H percentage change from Binance klines API
 * Uses 1-minute candles over the last 65 minutes to calculate the change
 * @param symbol - The base symbol (e.g., "BTC")
 * @param baseUrl - The Binance API base URL
 * @returns The 1H percentage change or null if unavailable
 */
async function fetchBinance1hChange(symbol: string, baseUrl: string): Promise<number | null> {
  const pairsToTry = [`${symbol}USDT`, `${symbol}FDUSD`, `${symbol}USD`];
  
  for (const pair of pairsToTry) {
    try {
      const url = `${baseUrl}/api/v3/klines?symbol=${pair}&interval=1m&limit=65`;
      const response = await fetch(url, {
        headers: {
          "Accept": "application/json",
          "User-Agent": "CryptoSage-Firebase/1.0",
        },
      });
      
      if (!response.ok) continue;
      
      const klines = await response.json();
      if (!Array.isArray(klines) || klines.length < 60) continue;
      
      // Binance klines format: [open_time, open, high, low, close, volume, close_time, ...]
      // Get the close price from ~60 minutes ago and the latest close
      const indexForOneHourAgo = Math.max(0, klines.length - 61);
      
      const parseClose = (arr: unknown[]): number | null => {
        if (!Array.isArray(arr) || arr.length <= 4) return null;
        const closeVal = arr[4];
        if (typeof closeVal === "string") {
          const v = parseFloat(closeVal);
          return v > 0 ? v : null;
        }
        if (typeof closeVal === "number" && closeVal > 0) return closeVal;
        return null;
      };
      
      const priceOneHourAgo = parseClose(klines[indexForOneHourAgo]);
      const currentPrice = parseClose(klines[klines.length - 1]);
      
      if (!priceOneHourAgo || !currentPrice) continue;
      
      const percentChange = ((currentPrice / priceOneHourAgo) - 1.0) * 100.0;
      
      // Sanity check: 1H changes should be within reasonable bounds
      if (!isFinite(percentChange) || Math.abs(percentChange) > 100) continue;
      
      return percentChange;
    } catch {
      continue;
    }
  }
  
  return null;
}

/**
 * Fetch 1H changes for multiple symbols in parallel with rate limiting
 * @param symbols - Array of base symbols
 * @param baseUrl - The Binance API base URL
 * @returns Map of symbol to 1H change
 */
async function fetchBatch1hChanges(
  symbols: string[],
  baseUrl: string
): Promise<Record<string, number>> {
  const result: Record<string, number> = {};
  
  // Process in batches of 5 to avoid rate limiting
  const batchSize = 5;
  for (let i = 0; i < symbols.length; i += batchSize) {
    const batch = symbols.slice(i, i + batchSize);
    const promises = batch.map(async (symbol) => {
      const change = await fetchBinance1hChange(symbol, baseUrl);
      if (change !== null) {
        result[symbol] = change;
      }
    });
    await Promise.all(promises);
    
    // Small delay between batches to be kind to the API
    if (i + batchSize < symbols.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  return result;
}

/**
 * Sync market data to Firestore every 30 seconds
 * This creates a SINGLE SOURCE OF TRUTH for all devices
 * All iOS devices listen to this document for consistent heat map data
 * 
 * Benefits:
 * - All devices see identical data (no more inconsistent heat maps)
 * - Reduces API calls (one server polls, all clients listen)
 * - Real-time updates via Firestore listeners
 * - Built-in offline support
 * - NOW INCLUDES 1H CHANGES for top coins (consistent across all devices)
 */
export const syncMarketDataToFirestore = onSchedule({
  schedule: "every 1 minutes",
  timeZone: "UTC",
  region: "us-east1", // Separate region to avoid quota conflicts with other functions
  memory: "512MiB", // Increased for CoinGecko 250-coin response with sparklines
  timeoutSeconds: 55,
  retryCount: 3, // Retry on transient failures
}, async () => {
  console.log("[syncMarketDataToFirestore] Starting market data sync...");
  
  try {
    // Fetch from Binance (same logic as getBinance24hrTickers)
    const endpoints = [
      { base: "https://api.binance.us", name: "Binance US" },
      { base: "https://api.binance.com", name: "Binance Global" },
    ];
    
    let tickers: Array<{
      symbol: string;
      lastPrice: string;
      priceChangePercent: string;
      volume: string;
      quoteVolume: string;
    }> = [];
    
    for (const endpoint of endpoints) {
      try {
        const url = `${endpoint.base}/api/v3/ticker/24hr`;
        console.log(`[syncMarketDataToFirestore] Trying ${endpoint.name}...`);
        
        const response = await fetch(url, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "CryptoSage-Firebase/1.0",
          },
        });
        
        if (response.status === 451 || response.status === 403) {
          console.log(`[syncMarketDataToFirestore] ${endpoint.name}: geo-blocked`);
          continue;
        }
        
        if (!response.ok) {
          console.log(`[syncMarketDataToFirestore] ${endpoint.name}: HTTP ${response.status}`);
          continue;
        }
        
        const allTickers = await response.json();
        
        // Filter to USD/USDT pairs only
        tickers = allTickers.filter((t: { symbol: string }) => 
          (t.symbol.endsWith("USDT") || t.symbol.endsWith("USD")) && 
          !t.symbol.includes("UP") && !t.symbol.includes("DOWN") &&
          !t.symbol.includes("BULL") && !t.symbol.includes("BEAR")
        );
        
        console.log(`[syncMarketDataToFirestore] Got ${tickers.length} tickers from ${endpoint.name}`);
        break;
        
      } catch (fetchError) {
        console.log(`[syncMarketDataToFirestore] ${endpoint.name} error: ${(fetchError as Error).message}`);
        continue;
      }
    }
    
    if (tickers.length === 0) {
      console.error("[syncMarketDataToFirestore] All endpoints failed, skipping update");
      return;
    }
    
    // Transform to a map format optimized for iOS consumption
    // Key: base symbol (BTC, ETH), Value: price data
    const tickerMap: Record<string, {
      price: number;
      change24h: number;
      change1h?: number;  // NEW: 1H change for consistency across devices
      volume: number;
      quoteVolume: number;
      symbol: string;
    }> = {};
    
    for (const t of tickers) {
      // Extract base symbol (BTCUSDT -> BTC, ETHUSD -> ETH)
      const base = t.symbol.replace(/USDT$|USD$|BUSD$|USDC$/, "");
      if (!base) continue;
      
      const price = parseFloat(t.lastPrice);
      const change24h = parseFloat(t.priceChangePercent);
      const volume = parseFloat(t.volume);
      const quoteVolume = parseFloat(t.quoteVolume);
      
      // Only keep valid data, prefer USDT pairs
      if (!isNaN(price) && price > 0) {
        // If we already have this symbol from a USD pair, prefer USDT (more liquidity)
        if (tickerMap[base] && t.symbol.endsWith("USD") && !t.symbol.endsWith("USDT")) {
          continue;
        }
        
        tickerMap[base] = {
          price,
          change24h: isNaN(change24h) ? 0 : change24h,
          volume: isNaN(volume) ? 0 : volume,
          quoteVolume: isNaN(quoteVolume) ? 0 : quoteVolume,
          symbol: t.symbol,
        };
      }
    }
    
    // NEW: Fetch 1H changes for top coins using Binance klines API
    // This ensures all devices see consistent 1H percentages
    const binanceBaseUrl = "https://api.binance.com"; // Use global endpoint for klines
    const coinsInTickers = TOP_COINS_FOR_1H.filter(coin => tickerMap[coin]);
    
    if (coinsInTickers.length > 0) {
      console.log(`[syncMarketDataToFirestore] Fetching 1H changes for ${coinsInTickers.length} top coins...`);
      
      try {
        const changes1h = await fetchBatch1hChanges(coinsInTickers, binanceBaseUrl);
        const count1h = Object.keys(changes1h).length;
        
        // Merge 1H changes into tickerMap
        for (const [symbol, change1h] of Object.entries(changes1h)) {
          if (tickerMap[symbol]) {
            tickerMap[symbol].change1h = change1h;
          }
        }
        
        console.log(`[syncMarketDataToFirestore] Added 1H changes for ${count1h} coins`);
      } catch (err1h) {
        // Don't fail the sync if 1H fetch fails - 24H data is still valuable
        console.log(`[syncMarketDataToFirestore] 1H fetch failed (non-critical): ${(err1h as Error).message}`);
      }
    }
    
    // Write to Firestore - this is the SINGLE SOURCE OF TRUTH
    const marketDataRef = db.collection("marketData").doc("heatmap");
    
    await marketDataRef.set({
      tickers: tickerMap,
      tickerCount: Object.keys(tickerMap).length,
      source: "binance",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedAt: new Date().toISOString(),
    });
    
    console.log(`[syncMarketDataToFirestore] Successfully synced ${Object.keys(tickerMap).length} tickers to Firestore`);
    
    // NOTE: CoinGecko calls (global stats + market data) have been moved to
    // syncCoinGeckoToFirestore which runs every 5 minutes instead of every 1 minute.
    // This reduces CoinGecko API usage by ~80% (from ~86k calls/month to ~17k).
    // Binance data (free, unlimited) still syncs every 1 minute for real-time prices.
    
  } catch (error) {
    console.error("[syncMarketDataToFirestore] Error:", error);
  }
});

// ============================================================================
// COINGECKO MARKET DATA SYNC (Separated from Binance - runs less frequently)
// ============================================================================

/**
 * Sync CoinGecko market data to Firestore every 5 minutes.
 * 
 * RATE LIMIT FIX: This was previously part of syncMarketDataToFirestore which ran
 * every 1 minute. CoinGecko's free Demo tier has a monthly credit quota (~10k calls).
 * Running 2 CoinGecko calls every minute = ~86,400 calls/month = 8x over quota!
 * 
 * By separating CoinGecko into its own 5-minute schedule:
 * - CoinGecko calls drop from ~86,400/month to ~17,280/month
 * - Combined with sentiment fix, total drops to ~8,640/month (under free quota)
 * - Binance heatmap data still syncs every 1 minute (free, no quota)
 * - Market caps, sparklines, and global stats don't change meaningfully in 5 minutes
 * 
 * Data synced:
 * - Global market stats (total market cap, BTC dominance, etc.)
 * - 250 coins with sparklines, market caps, and 1h/24h/7d percentages
 */
export const syncCoinGeckoToFirestore = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "UTC",
  region: "us-east1",
  memory: "512MiB",
  timeoutSeconds: 55,
  retryCount: 2,
}, async () => {
  console.log("[syncCoinGeckoToFirestore] Starting CoinGecko data sync...");
  
  try {
    // PHASE 1: Global market stats
    try {
      const globalResponse = await fetchCoinGeckoTracked(
        "https://api.coingecko.com/api/v3/global",
        "syncCoinGeckoToFirestore",
        "global"
      );
      
      if (globalResponse.ok) {
        const globalData = await globalResponse.json();
        const global = globalData.data;
        
        if (global) {
          const globalStatsRef = db.collection("marketData").doc("globalStats");
          await globalStatsRef.set({
            totalMarketCap: global.total_market_cap?.usd || 0,
            totalVolume24h: global.total_volume?.usd || 0,
            btcDominance: global.market_cap_percentage?.btc || 0,
            ethDominance: global.market_cap_percentage?.eth || 0,
            marketCapChange24h: global.market_cap_change_percentage_24h_usd || 0,
            activeCryptocurrencies: global.active_cryptocurrencies || 0,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            syncedAt: new Date().toISOString(),
            source: "coingecko",
          });
          console.log("[syncCoinGeckoToFirestore] Global stats synced successfully");
        }
      } else if (globalResponse.status === 429) {
        console.log("[syncCoinGeckoToFirestore] Global stats: rate limited (429) - will retry next cycle");
      }
    } catch (globalError) {
      console.log("[syncCoinGeckoToFirestore] Global stats sync failed (non-critical):", (globalError as Error).message);
    }
    
    // PHASE 2: Full market data with sparklines and percentages
    try {
      console.log("[syncCoinGeckoToFirestore] Fetching CoinGecko market data...");
      
      const cgUrl = new URL("https://api.coingecko.com/api/v3/coins/markets");
      cgUrl.searchParams.set("vs_currency", "usd");
      cgUrl.searchParams.set("order", "market_cap_desc");
      cgUrl.searchParams.set("per_page", "250");
      cgUrl.searchParams.set("page", "1");
      cgUrl.searchParams.set("sparkline", "true");
      cgUrl.searchParams.set("price_change_percentage", "1h,24h,7d");
      
      const cgResponse = await fetchCoinGeckoTracked(
        cgUrl.toString(),
        "syncCoinGeckoToFirestore",
        "coins_markets"
      );
      
      if (cgResponse.ok) {
        const coins = await cgResponse.json();
        
        if (Array.isArray(coins) && coins.length > 0) {
          const coingeckoRef = db.collection("marketData").doc("coingeckoMarkets");
          
          await coingeckoRef.set({
            coins: coins,
            coinCount: coins.length,
            source: "coingecko-demo",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            syncedAt: new Date().toISOString(),
          });
          
          console.log(`[syncCoinGeckoToFirestore] Synced ${coins.length} coins with sparklines to Firestore`);
        } else {
          console.log("[syncCoinGeckoToFirestore] CoinGecko response was empty or not an array");
        }
      } else if (cgResponse.status === 429) {
        console.log("[syncCoinGeckoToFirestore] CoinGecko: rate limited (429) - will retry next cycle");
      } else {
        console.log(`[syncCoinGeckoToFirestore] CoinGecko: HTTP ${cgResponse.status}`);
      }
    } catch (cgError) {
      console.log("[syncCoinGeckoToFirestore] CoinGecko market sync failed:", (cgError as Error).message);
    }
    
  } catch (error) {
    console.error("[syncCoinGeckoToFirestore] Error:", error);
  }
});

/**
 * HTTP callable function to get real-time market data
 * Reads from Firestore (single source of truth) with fallback to direct API
 * This ensures all devices get identical data
 */
export const getRealtimeMarketData = onCall({
  region: "us-east1", // Same region as sync function for consistency
  timeoutSeconds: 15,
  memory: "128MiB",
  maxInstances: 10, // Limit concurrent instances to control costs
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Read from Firestore (single source of truth)
    const marketDataRef = db.collection("marketData").doc("heatmap");
    const doc = await marketDataRef.get();
    
    if (doc.exists) {
      const data = doc.data();
      
      // Check if data is fresh (within last 2 minutes)
      const updatedAt = data?.updatedAt?.toMillis() || 0;
      const ageMs = Date.now() - updatedAt;
      const isFresh = ageMs < 120000; // 2 minutes
      
      if (data?.tickers && Object.keys(data.tickers).length > 0) {
        return {
          tickers: data.tickers,
          tickerCount: data.tickerCount || Object.keys(data.tickers).length,
          source: data.source || "binance",
          updatedAt: data.updatedAt?.toDate().toISOString(),
          syncedAt: data.syncedAt,
          cached: true,
          fresh: isFresh,
          ageSeconds: Math.round(ageMs / 1000),
        };
      }
    }
    
    // Fallback: trigger a manual fetch (should rarely happen)
    console.log("[getRealtimeMarketData] No cached data, fetching directly...");
    
    // Use the same fetch logic as the scheduled function
    const response = await fetch("https://api.binance.us/api/v3/ticker/24hr", {
      headers: {
        "Accept": "application/json",
        "User-Agent": "CryptoSage-Firebase/1.0",
      },
    });
    
    if (!response.ok) {
      throw new HttpsError("internal", "Failed to fetch market data");
    }
    
    const allTickers = await response.json();
    const tickers = allTickers.filter((t: { symbol: string }) => 
      (t.symbol.endsWith("USDT") || t.symbol.endsWith("USD")) && 
      !t.symbol.includes("UP") && !t.symbol.includes("DOWN")
    );
    
    const tickerMap: Record<string, {
      price: number;
      change24h: number;
      volume: number;
      quoteVolume: number;
      symbol: string;
    }> = {};
    
    for (const t of tickers) {
      const base = t.symbol.replace(/USDT$|USD$|BUSD$|USDC$/, "");
      if (!base) continue;
      
      const price = parseFloat(t.lastPrice);
      const change24h = parseFloat(t.priceChangePercent);
      
      if (!isNaN(price) && price > 0) {
        if (tickerMap[base] && t.symbol.endsWith("USD") && !t.symbol.endsWith("USDT")) {
          continue;
        }
        
        tickerMap[base] = {
          price,
          change24h: isNaN(change24h) ? 0 : change24h,
          volume: parseFloat(t.volume) || 0,
          quoteVolume: parseFloat(t.quoteVolume) || 0,
          symbol: t.symbol,
        };
      }
    }
    
    // Write to Firestore for future requests
    await marketDataRef.set({
      tickers: tickerMap,
      tickerCount: Object.keys(tickerMap).length,
      source: "binance",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedAt: new Date().toISOString(),
    });
    
    return {
      tickers: tickerMap,
      tickerCount: Object.keys(tickerMap).length,
      source: "binance",
      updatedAt: new Date().toISOString(),
      cached: false,
      fresh: true,
      ageSeconds: 0,
    };
    
  } catch (error) {
    throw safeError(error, "getRealtimeMarketData");
  }
});

// ============================================================================
// ORDER BOOK PROXY (Scalable Order Book Data)
// ============================================================================

/**
 * Order book cache duration - very short for real-time feel
 * 500ms cache means max 2 API calls/second to Binance, regardless of user count
 */
const ORDER_BOOK_CACHE_MS = 500;

/**
 * Top coins that most users will view - we pre-cache these
 */
const TOP_ORDER_BOOK_SYMBOLS = [
  "BTC", "ETH", "SOL", "XRP", "DOGE", "ADA", "AVAX", "SHIB", "DOT", "LINK",
  "MATIC", "UNI", "LTC", "BCH", "ATOM", "XLM", "NEAR", "APT", "OP", "ARB",
];

/**
 * Get order book depth data with Firebase caching
 * 
 * SCALABILITY: This function ensures that regardless of how many users
 * are viewing the order book for a coin, we only make 1 API call per 500ms.
 * 
 * Without this proxy:
 * - 1000 users viewing BTC order book = 1000 API calls/second
 * - Would hit Binance rate limit (1200/min) in 1.2 seconds
 * 
 * With this proxy:
 * - 1000 users viewing BTC order book = 2 API calls/second (from Firebase)
 * - All users get identical data
 * - Never hits rate limits
 * 
 * Security: Rate limited, input validated
 */
export const getOrderBookDepth = onCall({
  timeoutSeconds: 10,
  memory: "128MiB",
  maxInstances: 20, // Higher limit for real-time data
  region: "us-central1",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting - use publicMarket tier
    await checkRateLimit(clientIP, "publicMarket");
    
    // Validate input
    const symbol = sanitizeString(request.data?.symbol || "BTC").toUpperCase();
    if (!validateCoinSymbol(symbol)) {
      throw new HttpsError("invalid-argument", "Invalid symbol");
    }
    
    // Depth limit (5, 10, 20, 50, 100, 500, 1000)
    const limitParam = validateNumber(request.data?.limit, 20, 5, 100);
    
    // EXCHANGE SELECTION: Accept optional exchange parameter
    // Supported: binance, coinbase, kraken, kucoin (default: binance)
    const exchangeParam = sanitizeString(request.data?.exchange || "binance").toLowerCase();
    const validExchanges = ["binance", "coinbase", "kraken", "kucoin"];
    const preferredExchange = validExchanges.includes(exchangeParam) ? exchangeParam : "binance";
    
    // Check cache first (keyed by exchange for exchange-specific data)
    const cacheKey = `orderbook_${symbol}_${limitParam}_${preferredExchange}`;
    const cacheRef = db.collection("orderBookCache").doc(cacheKey);
    const cached = await cacheRef.get();
    
    if (cached.exists) {
      const data = cached.data();
      const age = Date.now() - (data?.timestamp || 0);
      
      // Return cached data if fresh (within 500ms)
      if (age < ORDER_BOOK_CACHE_MS && data?.bids && data?.asks) {
        return {
          symbol,
          bids: data.bids,
          asks: data.asks,
          lastUpdateId: data.lastUpdateId,
          timestamp: data.timestamp,
          cached: true,
          ageMs: age,
          source: data.source || preferredExchange,
        };
      }
    }
    
    let orderBook: {
      bids: Array<[string, string]>;
      asks: Array<[string, string]>;
      lastUpdateId: number;
    } | null = null;
    let source = preferredExchange;
    
    // Helper function to fetch from Binance
    const fetchBinance = async (): Promise<typeof orderBook> => {
      const endpoints = [
        { base: "https://api.binance.us", name: "binance.us" },
        { base: "https://api.binance.com", name: "binance.com" },
      ];
      
      for (const endpoint of endpoints) {
        try {
          const url = `${endpoint.base}/api/v3/depth?symbol=${symbol}USDT&limit=${limitParam}`;
          const response = await fetch(url, {
            headers: {
              "Accept": "application/json",
              "User-Agent": "CryptoSage-Firebase/1.0",
            },
          });
          
          if (response.status === 451 || response.status === 403) {
            console.log(`[getOrderBookDepth] ${endpoint.name}: geo-blocked`);
            continue;
          }
          
          if (!response.ok) {
            console.log(`[getOrderBookDepth] ${endpoint.name}: HTTP ${response.status}`);
            continue;
          }
          
          source = endpoint.name;
          return await response.json();
        } catch (err) {
          console.log(`[getOrderBookDepth] ${endpoint.name} error: ${(err as Error).message}`);
        }
      }
      return null;
    };
    
    // Helper function to fetch from Coinbase
    const fetchCoinbase = async (): Promise<typeof orderBook> => {
      try {
        const cbUrl = `https://api.exchange.coinbase.com/products/${symbol}-USD/book?level=2`;
        const cbResponse = await fetch(cbUrl, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "CryptoSage-Firebase/1.0",
          },
        });
        
        if (cbResponse.ok) {
          const cbData = await cbResponse.json();
          source = "coinbase";
          return {
            bids: (cbData.bids || []).slice(0, limitParam).map((b: [string, string, string]) => [b[0], b[1]]),
            asks: (cbData.asks || []).slice(0, limitParam).map((a: [string, string, string]) => [a[0], a[1]]),
            lastUpdateId: Date.now(),
          };
        }
      } catch (cbError) {
        console.log(`[getOrderBookDepth] Coinbase error: ${(cbError as Error).message}`);
      }
      return null;
    };
    
    // Helper function to fetch from Kraken
    const fetchKraken = async (): Promise<typeof orderBook> => {
      try {
        // Kraken uses XBT for Bitcoin
        const krakenSymbol = symbol === "BTC" ? "XBT" : symbol;
        const krakenUrl = `https://api.kraken.com/0/public/Depth?pair=${krakenSymbol}USD&count=${limitParam}`;
        const response = await fetch(krakenUrl, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "CryptoSage-Firebase/1.0",
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          // Kraken format: {"result": {"XXBTZUSD": {"bids": [[price, volume, timestamp], ...], "asks": [...]}}}
          if (data.result) {
            const pairData = Object.values(data.result)[0] as { bids: Array<[string, string, number]>; asks: Array<[string, string, number]> };
            if (pairData && pairData.bids && pairData.asks) {
              source = "kraken";
              return {
                bids: pairData.bids.slice(0, limitParam).map((b: [string, string, number]) => [b[0], b[1]]),
                asks: pairData.asks.slice(0, limitParam).map((a: [string, string, number]) => [a[0], a[1]]),
                lastUpdateId: Date.now(),
              };
            }
          }
        }
      } catch (krakenError) {
        console.log(`[getOrderBookDepth] Kraken error: ${(krakenError as Error).message}`);
      }
      return null;
    };
    
    // Helper function to fetch from KuCoin
    const fetchKuCoin = async (): Promise<typeof orderBook> => {
      try {
        const kucoinUrl = `https://api.kucoin.com/api/v1/market/orderbook/level2_20?symbol=${symbol}-USDT`;
        const response = await fetch(kucoinUrl, {
          headers: {
            "Accept": "application/json",
            "User-Agent": "CryptoSage-Firebase/1.0",
          },
        });
        
        if (response.ok) {
          const data = await response.json();
          // KuCoin format: {"data": {"bids": [[price, size], ...], "asks": [[price, size], ...]}}
          if (data.data && data.data.bids && data.data.asks) {
            source = "kucoin";
            return {
              bids: data.data.bids.slice(0, limitParam).map((b: [string, string]) => [b[0], b[1]]),
              asks: data.data.asks.slice(0, limitParam).map((a: [string, string]) => [a[0], a[1]]),
              lastUpdateId: Date.now(),
            };
          }
        }
      } catch (kucoinError) {
        console.log(`[getOrderBookDepth] KuCoin error: ${(kucoinError as Error).message}`);
      }
      return null;
    };
    
    // Fetch from preferred exchange first, then fallback to others
    switch (preferredExchange) {
      case "coinbase":
        orderBook = await fetchCoinbase();
        if (!orderBook) orderBook = await fetchBinance();
        if (!orderBook) orderBook = await fetchKraken();
        break;
      case "kraken":
        orderBook = await fetchKraken();
        if (!orderBook) orderBook = await fetchBinance();
        if (!orderBook) orderBook = await fetchCoinbase();
        break;
      case "kucoin":
        orderBook = await fetchKuCoin();
        if (!orderBook) orderBook = await fetchBinance();
        if (!orderBook) orderBook = await fetchCoinbase();
        break;
      default: // binance
        orderBook = await fetchBinance();
        if (!orderBook) orderBook = await fetchCoinbase();
        if (!orderBook) orderBook = await fetchKraken();
    }
    
    if (!orderBook) {
      // Return stale cache if available, even if expired
      if (cached.exists) {
        const data = cached.data();
        return {
          symbol,
          bids: data?.bids || [],
          asks: data?.asks || [],
          lastUpdateId: data?.lastUpdateId || 0,
          timestamp: data?.timestamp || 0,
          cached: true,
          stale: true,
          ageMs: Date.now() - (data?.timestamp || 0),
          source: data?.source || "cache",
        };
      }
      throw new HttpsError("unavailable", "Order book data unavailable");
    }
    
    const timestamp = Date.now();
    
    // Cache the result (fire and forget to not slow down response)
    cacheRef.set({
      bids: orderBook.bids,
      asks: orderBook.asks,
      lastUpdateId: orderBook.lastUpdateId,
      timestamp,
      source,
    }).catch(err => console.log(`[getOrderBookDepth] Cache write error: ${err.message}`));
    
    return {
      symbol,
      bids: orderBook.bids,
      asks: orderBook.asks,
      lastUpdateId: orderBook.lastUpdateId,
      timestamp,
      cached: false,
      ageMs: 0,
      source,
    };
    
  } catch (error) {
    throw safeError(error, "getOrderBookDepth");
  }
});

/**
 * Scheduled function to pre-warm order book cache for top coins
 * Runs every 30 seconds to ensure cache is always fresh for popular coins
 * 
 * This reduces latency for the most viewed order books
 */
export const warmOrderBookCache = onSchedule({
  schedule: "every 1 minutes",  // Minimum allowed by Cloud Scheduler
  timeZone: "UTC",
  region: "us-central1",
  memory: "256MiB",
  timeoutSeconds: 55,
}, async () => {
  console.log("[warmOrderBookCache] Pre-warming order book cache for top coins...");
  
  const endpoints = [
    { base: "https://api.binance.us", name: "binance.us" },
    { base: "https://api.binance.com", name: "binance.com" },
  ];
  
  let successCount = 0;
  let activeEndpoint = endpoints[0];
  
  // Find working endpoint first
  for (const endpoint of endpoints) {
    try {
      const testUrl = `${endpoint.base}/api/v3/depth?symbol=BTCUSDT&limit=5`;
      const response = await fetch(testUrl, {
        headers: { "User-Agent": "CryptoSage-Firebase/1.0" },
      });
      if (response.ok) {
        activeEndpoint = endpoint;
        break;
      }
    } catch {
      continue;
    }
  }
  
  // Fetch top 10 coins in parallel (with small batches to avoid rate limits)
  const topCoins = TOP_ORDER_BOOK_SYMBOLS.slice(0, 10);
  const batchSize = 5;
  
  for (let i = 0; i < topCoins.length; i += batchSize) {
    const batch = topCoins.slice(i, i + batchSize);
    
    await Promise.all(batch.map(async (symbol) => {
      try {
        const url = `${activeEndpoint.base}/api/v3/depth?symbol=${symbol}USDT&limit=20`;
        const response = await fetch(url, {
          headers: { "User-Agent": "CryptoSage-Firebase/1.0" },
        });
        
        if (!response.ok) return;
        
        const orderBook = await response.json();
        const timestamp = Date.now();
        const cacheKey = `orderbook_${symbol}_20`;
        
        await db.collection("orderBookCache").doc(cacheKey).set({
          bids: orderBook.bids,
          asks: orderBook.asks,
          lastUpdateId: orderBook.lastUpdateId,
          timestamp,
          source: activeEndpoint.name,
        });
        
        successCount++;
      } catch (err) {
        console.log(`[warmOrderBookCache] ${symbol} error: ${(err as Error).message}`);
      }
    }));
    
    // Small delay between batches to be nice to the API
    if (i + batchSize < topCoins.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  console.log(`[warmOrderBookCache] Cached ${successCount}/${topCoins.length} order books`);
});

// ============================================================================
// CHART DATA CACHING (All Users Get Same Chart Data)
// ============================================================================

/**
 * Chart cache durations per interval
 * Shorter intervals need fresher data, longer intervals can cache longer
 */
const CHART_CACHE_DURATIONS: Record<string, number> = {
  "1m": 30 * 1000,         // 30 seconds
  "5m": 60 * 1000,         // 1 minute
  "15m": 2 * 60 * 1000,    // 2 minutes
  "30m": 3 * 60 * 1000,    // 3 minutes
  "1h": 5 * 60 * 1000,     // 5 minutes
  "4h": 10 * 60 * 1000,    // 10 minutes
  "1d": 15 * 60 * 1000,    // 15 minutes
  "1w": 30 * 60 * 1000,    // 30 minutes
  "1M": 60 * 60 * 1000,    // 1 hour
  "3M": 2 * 60 * 60 * 1000,  // 2 hours
  "6M": 4 * 60 * 60 * 1000,  // 4 hours
  "1Y": 6 * 60 * 60 * 1000,  // 6 hours
  "3Y": 12 * 60 * 60 * 1000, // 12 hours
  "ALL": 24 * 60 * 60 * 1000, // 24 hours
};

// Map app intervals to Binance API intervals
const BINANCE_INTERVAL_MAP: Record<string, string> = {
  "1m": "1m", "5m": "5m", "15m": "15m", "30m": "30m",
  "1h": "1h", "4h": "4h", "1d": "1d", "1w": "1w", "1M": "1M",
  "3M": "1d", "6M": "1d", "1Y": "1d", "3Y": "1w", "ALL": "1w",
};

// Data point limits per interval
// IMPORTANT: These limits must accommodate the HIGHEST-need app timeframe that maps
// to each Binance interval. The iOS app uses high-resolution candles:
//   - 1W timeframe → "15m" candles → needs 722 (672 visible + 50 warmup)
//   - 4H timeframe → "30m" candles → needs 554 (504 visible + 50 warmup)
//   - 5m timeframe → "1m" candles  → needs 530 (480 visible + 50 warmup)
//   - 1D timeframe → "5m" candles  → needs 338 (288 visible + 50 warmup)
const CHART_LIMITS: Record<string, number> = {
  "1m": 550, "5m": 500, "15m": 750, "30m": 600,
  "1h": 500, "4h": 500, "1d": 500, "1w": 250, "1M": 60,
  "3M": 90, "6M": 180, "1Y": 365, "3Y": 156, "ALL": 500,
};

// Valid chart intervals
const VALID_CHART_INTERVALS = Object.keys(CHART_CACHE_DURATIONS);

/**
 * Get chart candlestick data with Firebase caching
 * 
 * This function provides:
 * - Centralized caching for all users (1 API call serves everyone)
 * - Rate limit protection (limits API calls to external services)
 * - Identical data across all devices
 * - Automatic fallback between Binance US/Global
 * 
 * Cache strategy:
 * - Short intervals (1m-30m): 30s-3min cache for real-time feel
 * - Medium intervals (1h-4h): 5-10min cache
 * - Long intervals (1d+): 15min-24h cache (data changes slowly)
 */
export const getChartData = onCall({
  timeoutSeconds: 30,
  memory: "512MiB",
  maxInstances: 20,
}, async (request) => {
  const clientIP = getClientIP(request);
  
  // Rate limiting
  await checkRateLimit(clientIP, "publicMarket");
  
  // Validate inputs
  const { symbol, interval, limit: requestedLimit } = request.data || {};
  
  if (!symbol || typeof symbol !== "string") {
    throw new HttpsError("invalid-argument", "Symbol is required");
  }
  
  if (!interval || typeof interval !== "string" || !VALID_CHART_INTERVALS.includes(interval)) {
    throw new HttpsError("invalid-argument", `Invalid interval. Must be one of: ${VALID_CHART_INTERVALS.join(", ")}`);
  }
  
  // Normalize symbol (uppercase, remove special chars)
  const cleanSymbol = symbol.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (cleanSymbol.length < 1 || cleanSymbol.length > 10) {
    throw new HttpsError("invalid-argument", "Invalid symbol format");
  }
  
  // Create cache key
  const cacheKey = `chart_${cleanSymbol}_${interval}`;
  const cacheRef = db.collection("chartDataCache").doc(cacheKey);
  const cacheDuration = CHART_CACHE_DURATIONS[interval] || 5 * 60 * 1000;
  
  try {
    // Determine minimum acceptable point count for this interval
    const minAcceptablePoints = Math.floor((CHART_LIMITS[interval] || 500) * 0.8);
    
    // Check cache first
    const cached = await cacheRef.get();
    
    if (cached.exists) {
      const data = cached.data();
      const cachedPointCount = data?.points?.length || 0;
      
      // Return cache if: time-valid AND has enough data points
      // This prevents serving under-populated cache entries when a higher-limit request comes in
      if (data && isCacheValid(data.updatedAt, cacheDuration) && cachedPointCount >= minAcceptablePoints) {
        console.log(`[getChartData] Cache HIT for ${cacheKey} (${cachedPointCount} points)`);
        return {
          symbol: cleanSymbol,
          interval,
          points: data.points || [],
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
          source: data.source || "cache",
        };
      }
      
      if (data && isCacheValid(data.updatedAt, cacheDuration) && cachedPointCount < minAcceptablePoints) {
        console.log(`[getChartData] Cache has only ${cachedPointCount} points (need ${minAcceptablePoints}+), re-fetching...`);
      }
    }
    
    // Cache miss, stale, or insufficient data - need to fetch
    console.log(`[getChartData] Cache MISS for ${cacheKey}, fetching from API...`);
    
    // Request coalescing - only one request fetches
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      // Another request is fetching, wait for cache
      console.log(`[getChartData] Waiting for another request to fetch ${cacheKey}`);
      const { data, timedOut } = await waitForCachedData(cacheRef, cacheDuration, 15000);
      
      if (data && !timedOut) {
        return {
          symbol: cleanSymbol,
          interval,
          points: data.points || [],
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
          source: "coalesced",
        };
      }
      // Timed out waiting, proceed to fetch ourselves
    }
    
    try {
      // Fetch from Binance (try US first, then Global)
      const endpoints = [
        { base: "https://api.binance.us", name: "Binance US" },
        { base: "https://api.binance.com", name: "Binance Global" },
      ];
      
      const binanceInterval = BINANCE_INTERVAL_MAP[interval] || "1d";
      // Use the HIGHER of the default limit and client-requested limit (capped at 1000 Binance max)
      // This ensures the cache always has enough data for the most demanding timeframe
      const defaultLimit = CHART_LIMITS[interval] || 500;
      const clientLimit = (typeof requestedLimit === "number" && requestedLimit > 0) ? requestedLimit : 0;
      const limit = Math.min(Math.max(defaultLimit, clientLimit, 16), 1000);
      
      // Build trading pair (try USDT first, then USD)
      const pairs = cleanSymbol.includes("USD") ? [cleanSymbol] : 
                    [`${cleanSymbol}USDT`, `${cleanSymbol}USD`];
      
      let points: Array<{t: number; o: number; h: number; l: number; c: number; v: number}> = [];
      let source = "";
      let lastError = "";
      
      // Try each endpoint
      for (const endpoint of endpoints) {
        // Try each pair
        for (const pair of pairs) {
          try {
            const url = `${endpoint.base}/api/v3/klines?symbol=${pair}&interval=${binanceInterval}&limit=${limit}`;
            console.log(`[getChartData] Trying ${endpoint.name}: ${url}`);
            
            const response = await fetch(url, {
              headers: {
                "Accept": "application/json",
                "User-Agent": "CryptoSage-Firebase/1.0",
              },
            });
            
            if (response.status === 451) {
              lastError = `${endpoint.name}: geo-blocked`;
              continue; // Try next endpoint
            }
            
            if (response.status === 429) {
              lastError = `${endpoint.name}: rate limited`;
              // Return stale cache if available
              if (cached.exists && cached.data()?.points?.length > 0) {
                console.log(`[getChartData] Rate limited, returning stale cache`);
                return {
                  symbol: cleanSymbol,
                  interval,
                  points: cached.data()?.points || [],
                  cached: true,
                  stale: true,
                  updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
                  source: "stale",
                };
              }
              continue;
            }
            
            if (!response.ok) {
              lastError = `${endpoint.name}/${pair}: HTTP ${response.status}`;
              continue;
            }
            
            const klines = await response.json();
            
            if (!Array.isArray(klines) || klines.length === 0) {
              lastError = `${endpoint.name}/${pair}: no data`;
              continue;
            }
            
            // Parse klines: [openTime, open, high, low, close, volume, closeTime, ...]
            points = klines.map((k: unknown[]) => ({
              t: Number(k[0]),           // Open time (ms)
              o: parseFloat(String(k[1])), // Open
              h: parseFloat(String(k[2])), // High
              l: parseFloat(String(k[3])), // Low
              c: parseFloat(String(k[4])), // Close
              v: parseFloat(String(k[5])), // Volume
            })).filter((p: {c: number}) => p.c > 0);
            
            source = `${endpoint.name}/${pair}`;
            console.log(`[getChartData] Success: ${points.length} points from ${source}`);
            break; // Success!
            
          } catch (fetchError) {
            lastError = `${endpoint.name}/${pair}: ${(fetchError as Error).message}`;
            continue;
          }
        }
        
        if (points.length > 0) break; // Got data, exit endpoint loop
      }
      
      // If no data fetched
      if (points.length === 0) {
        // Return stale cache if available
        if (cached.exists && cached.data()?.points?.length > 0) {
          console.log(`[getChartData] All fetches failed, returning stale cache. Last error: ${lastError}`);
          return {
            symbol: cleanSymbol,
            interval,
            points: cached.data()?.points || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
            source: "stale",
          };
        }
        
        throw new HttpsError("unavailable", `Could not fetch chart data for ${cleanSymbol}. ${lastError}`);
      }
      
      // Cache the new data
      await cacheRef.set({
        symbol: cleanSymbol,
        interval,
        points,
        source,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        symbol: cleanSymbol,
        interval,
        points,
        cached: false,
        updatedAt: new Date().toISOString(),
        source,
      };
      
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
    
  } catch (error) {
    throw safeError(error, "getChartData");
  }
});

/**
 * Get chart data for CoinGecko (for 3Y and ALL timeframes)
 * CoinGecko provides longer historical data than Binance
 */
export const getChartDataCoinGecko = onCall({
  timeoutSeconds: 30,
  memory: "512MiB",
  maxInstances: 10,
}, async (request) => {
  const clientIP = getClientIP(request);
  await checkRateLimit(clientIP, "publicMarket");
  
  const { coinId, days } = request.data || {};
  
  if (!coinId || typeof coinId !== "string") {
    throw new HttpsError("invalid-argument", "CoinGecko coinId is required");
  }
  
  // Sanitize coinId
  const cleanCoinId = coinId.toLowerCase().replace(/[^a-z0-9-]/g, "");
  if (cleanCoinId.length < 1 || cleanCoinId.length > 50) {
    throw new HttpsError("invalid-argument", "Invalid coinId format");
  }
  
  // Determine days and cache duration
  const requestedDays = days === "max" ? "max" : Math.min(Math.max(1, parseInt(days) || 365), 3650);
  const cacheKey = `coingecko_${cleanCoinId}_${requestedDays}`;
  const cacheRef = db.collection("chartDataCache").doc(cacheKey);
  
  // Cache longer for historical data (changes slowly)
  const cacheDuration = requestedDays === "max" ? 24 * 60 * 60 * 1000 : // 24h for max
                        typeof requestedDays === "number" && requestedDays > 365 ? 12 * 60 * 60 * 1000 : // 12h for >1Y
                        6 * 60 * 60 * 1000; // 6h for others
  
  try {
    // Check cache
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, cacheDuration)) {
        console.log(`[getChartDataCoinGecko] Cache HIT for ${cacheKey}`);
        return {
          coinId: cleanCoinId,
          days: requestedDays,
          prices: data.prices || [],
          volumes: data.volumes || [],
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
        };
      }
    }
    
    // Cache miss - fetch from CoinGecko
    console.log(`[getChartDataCoinGecko] Cache MISS for ${cacheKey}, fetching...`);
    
    const acquiredLock = await tryAcquireFetchLock(cacheKey);
    
    if (!acquiredLock) {
      const { data, timedOut } = await waitForCachedData(cacheRef, cacheDuration, 15000);
      if (data && !timedOut) {
        return {
          coinId: cleanCoinId,
          days: requestedDays,
          prices: data.prices || [],
          volumes: data.volumes || [],
          cached: true,
          updatedAt: data.updatedAt?.toDate().toISOString(),
        };
      }
    }
    
    try {
      const url = `https://api.coingecko.com/api/v3/coins/${cleanCoinId}/market_chart?vs_currency=usd&days=${requestedDays}`;
      
      const response = await fetchCoinGeckoTracked(
        url,
        "getChartDataCoinGecko",
        "market_chart"
      );
      
      if (response.status === 429) {
        // Return stale cache
        if (cached.exists && cached.data()?.prices?.length > 0) {
          console.log(`[getChartDataCoinGecko] Rate limited, returning stale cache`);
          return {
            coinId: cleanCoinId,
            days: requestedDays,
            prices: cached.data()?.prices || [],
            volumes: cached.data()?.volumes || [],
            cached: true,
            stale: true,
            updatedAt: cached.data()?.updatedAt?.toDate().toISOString(),
          };
        }
        throw new HttpsError("resource-exhausted", "CoinGecko rate limit exceeded");
      }
      
      if (!response.ok) {
        throw new HttpsError("unavailable", `CoinGecko error: HTTP ${response.status}`);
      }
      
      const data = await response.json();
      
      // Extract prices and volumes
      // Format: prices: [[timestamp, price], ...], total_volumes: [[timestamp, volume], ...]
      const prices = (data.prices || []).map((p: number[]) => ({ t: p[0], p: p[1] }));
      const volumes = (data.total_volumes || []).map((v: number[]) => ({ t: v[0], v: v[1] }));
      
      // Cache the data
      await cacheRef.set({
        coinId: cleanCoinId,
        days: requestedDays,
        prices,
        volumes,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      console.log(`[getChartDataCoinGecko] Success: ${prices.length} prices, ${volumes.length} volumes`);
      
      return {
        coinId: cleanCoinId,
        days: requestedDays,
        prices,
        volumes,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
      
    } finally {
      if (acquiredLock) {
        await releaseFetchLock(cacheKey);
      }
    }
    
  } catch (error) {
    throw safeError(error, "getChartDataCoinGecko");
  }
});

// ============================================================================
// NEWS FEED SYNC (All Users Get Same News)
// ============================================================================

/**
 * Sync crypto news to Firestore every 5 minutes
 * This creates a SINGLE SOURCE OF TRUTH for news across all devices
 * Benefits:
 * - API keys stay on server (security)
 * - Reduces API calls (one fetch, all users read)
 * - All users see identical news feed
 * - Built-in caching and offline support via Firestore
 */
export const syncNewsToFirestore = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "UTC",
  region: "us-east1", // Separate region to avoid quota conflicts
  memory: "128MiB", // Optimized - news fetch is lightweight
  timeoutSeconds: 55,
  retryCount: 3, // Retry on transient failures
}, async () => {
  console.log("[syncNewsToFirestore] Starting news sync...");
  
  try {
    // Fetch from CryptoCompare News API (free, no key required for basic access)
    // This provides high-quality crypto news from reputable sources
    const newsUrl = "https://min-api.cryptocompare.com/data/v2/news/?lang=EN&sortOrder=latest";
    
    console.log("[syncNewsToFirestore] Fetching from CryptoCompare...");
    
    const response = await fetch(newsUrl, {
      headers: {
        "Accept": "application/json",
        "User-Agent": "CryptoSage-Firebase/1.0",
      },
    });
    
    if (!response.ok) {
      console.error(`[syncNewsToFirestore] CryptoCompare returned ${response.status}`);
      return;
    }
    
    const data = await response.json();
    
    if (!data.Data || !Array.isArray(data.Data)) {
      console.error("[syncNewsToFirestore] Invalid response format");
      return;
    }
    
    // Transform to our article format
    const articles = data.Data.slice(0, 50).map((item: {
      id: string;
      title: string;
      body: string;
      url: string;
      imageurl: string;
      source: string;
      published_on: number;
      categories: string;
    }) => ({
      id: item.id || `cc-${Date.now()}-${Math.random()}`,
      title: item.title || "",
      description: item.body?.substring(0, 300) || "",
      url: item.url || "",
      urlToImage: item.imageurl || null,
      sourceName: item.source || "CryptoCompare",
      publishedAt: item.published_on ? new Date(item.published_on * 1000).toISOString() : new Date().toISOString(),
      categories: item.categories || "",
    })).filter((a: { title: string; url: string }) => a.title && a.url);
    
    if (articles.length === 0) {
      console.log("[syncNewsToFirestore] No valid articles found");
      return;
    }
    
    // Write to Firestore
    const newsRef = db.collection("marketData").doc("news");
    
    await newsRef.set({
      articles,
      articleCount: articles.length,
      source: "cryptocompare",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedAt: new Date().toISOString(),
    });
    
    console.log(`[syncNewsToFirestore] Successfully synced ${articles.length} articles to Firestore`);
    
  } catch (error) {
    console.error("[syncNewsToFirestore] Error:", error);
  }
});

/**
 * HTTP callable function to get news from Firestore
 * Provides fallback if scheduled sync hasn't run yet
 */
export const getNews = onCall({
  region: "us-east1", // Same region as sync function for consistency
  timeoutSeconds: 15,
  memory: "128MiB",
  maxInstances: 10, // Limit concurrent instances to control costs
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, "publicMarket");
    
    // Read from Firestore (single source of truth)
    const newsRef = db.collection("marketData").doc("news");
    const doc = await newsRef.get();
    
    if (doc.exists) {
      const data = doc.data();
      
      // Check if data is fresh (within last 10 minutes)
      const updatedAt = data?.updatedAt?.toMillis() || 0;
      const ageMs = Date.now() - updatedAt;
      const isFresh = ageMs < 600000; // 10 minutes
      
      if (data?.articles && data.articles.length > 0) {
        return {
          articles: data.articles,
          articleCount: data.articleCount || data.articles.length,
          source: data.source || "cryptocompare",
          updatedAt: data.updatedAt?.toDate().toISOString(),
          cached: true,
          fresh: isFresh,
          ageSeconds: Math.round(ageMs / 1000),
        };
      }
    }
    
    // Fallback: fetch directly and cache
    console.log("[getNews] No cached news, fetching directly...");
    
    const newsUrl = "https://min-api.cryptocompare.com/data/v2/news/?lang=EN&sortOrder=latest";
    const response = await fetch(newsUrl, {
      headers: {
        "Accept": "application/json",
        "User-Agent": "CryptoSage-Firebase/1.0",
      },
    });
    
    if (!response.ok) {
      throw new HttpsError("internal", "Failed to fetch news");
    }
    
    const newsData = await response.json();
    
    if (!newsData.Data || !Array.isArray(newsData.Data)) {
      throw new HttpsError("internal", "Invalid news response");
    }
    
    const articles = newsData.Data.slice(0, 50).map((item: {
      id: string;
      title: string;
      body: string;
      url: string;
      imageurl: string;
      source: string;
      published_on: number;
      categories: string;
    }) => ({
      id: item.id || `cc-${Date.now()}-${Math.random()}`,
      title: item.title || "",
      description: item.body?.substring(0, 300) || "",
      url: item.url || "",
      urlToImage: item.imageurl || null,
      sourceName: item.source || "CryptoCompare",
      publishedAt: item.published_on ? new Date(item.published_on * 1000).toISOString() : new Date().toISOString(),
      categories: item.categories || "",
    })).filter((a: { title: string; url: string }) => a.title && a.url);
    
    // Cache for future requests
    await newsRef.set({
      articles,
      articleCount: articles.length,
      source: "cryptocompare",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      syncedAt: new Date().toISOString(),
    });
    
    return {
      articles,
      articleCount: articles.length,
      source: "cryptocompare",
      updatedAt: new Date().toISOString(),
      cached: false,
      fresh: true,
      ageSeconds: 0,
    };
    
  } catch (error) {
    throw safeError(error, "getNews");
  }
});

/**
 * Clean up old cache entries daily
 */
export const cleanupOldCache = onSchedule({
  schedule: "every 24 hours",
  timeZone: "UTC",
  memory: "256MiB",
}, async () => {
  console.log("Cleaning up old cache entries...");
  
  const cutoffTime = admin.firestore.Timestamp.fromMillis(
    Date.now() - 7 * 24 * 60 * 60 * 1000 // 7 days ago
  );
  
  try {
    // Clean up old AI cache entries
    const aiCacheSnapshot = await db.collection("sharedAICache")
      .where("updatedAt", "<", cutoffTime)
      .get();
    
    const batch = db.batch();
    aiCacheSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    // Clean up old market data cache
    const marketCacheSnapshot = await db.collection("marketDataCache")
      .where("updatedAt", "<", cutoffTime)
      .get();
    
    marketCacheSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    
    console.log(`Cleaned up ${aiCacheSnapshot.size + marketCacheSnapshot.size} old cache entries`);
    
    // SCALABILITY FIX: Clean up old rate limit entries (older than 1 hour)
    // These accumulate per-IP/user and can grow unbounded at scale
    const rateLimitCutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 60 * 60 * 1000 // 1 hour ago
    );
    
    const rateLimitsSnapshot = await db.collection("_rateLimits")
      .where("lastRequest", "<", rateLimitCutoff)
      .limit(500) // Batch limit to avoid timeout
      .get();
    
    if (rateLimitsSnapshot.size > 0) {
      const rateLimitBatch = db.batch();
      rateLimitsSnapshot.docs.forEach(doc => {
        rateLimitBatch.delete(doc.ref);
      });
      await rateLimitBatch.commit();
      console.log(`Cleaned up ${rateLimitsSnapshot.size} old rate limit entries`);
    }
    
    // SCALABILITY FIX: Clean up old audit log entries (older than 7 days)
    // These accumulate with every request and can grow very large at scale
    const auditLogCutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 7 * 24 * 60 * 60 * 1000 // 7 days ago
    );
    
    const auditLogsSnapshot = await db.collection("_auditLogs")
      .where("timestamp", "<", auditLogCutoff)
      .limit(500) // Batch limit to avoid timeout
      .get();
    
    if (auditLogsSnapshot.size > 0) {
      const auditBatch = db.batch();
      auditLogsSnapshot.docs.forEach(doc => {
        auditBatch.delete(doc.ref);
      });
      await auditBatch.commit();
      console.log(`Cleaned up ${auditLogsSnapshot.size} old audit log entries`);
    }
    
    // SCALABILITY FIX: Clean up stale fetch locks (older than 1 minute)
    // These should normally be released immediately, but clean up any stale ones
    const fetchLockCutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 60 * 1000 // 1 minute ago
    );
    
    const fetchLocksSnapshot = await db.collection("_fetchLocks")
      .where("lockedAt", "<", fetchLockCutoff)
      .limit(500)
      .get();
    
    if (fetchLocksSnapshot.size > 0) {
      const fetchLockBatch = db.batch();
      fetchLocksSnapshot.docs.forEach(doc => {
        fetchLockBatch.delete(doc.ref);
      });
      await fetchLockBatch.commit();
      console.log(`Cleaned up ${fetchLocksSnapshot.size} stale fetch locks`);
    }
    
  } catch (error) {
    console.error("Error cleaning up cache:", error);
  }
});

// ============================================================================
// PREDICTION ACCURACY EVALUATION
// ============================================================================

/**
 * Evaluate expired predictions hourly
 * Fetches actual prices and compares against predicted values
 * Updates global accuracy metrics
 */
export const evaluatePredictionOutcomes = onSchedule({
  schedule: "every 1 hours",
  timeZone: "UTC",
  memory: "512MiB",
  timeoutSeconds: 300,
}, async () => {
  console.log("Evaluating expired prediction outcomes...");
  
  try {
    const now = admin.firestore.Timestamp.now();
    
    // Query predictions that have expired but haven't been evaluated yet
    const pendingPredictions = await db.collection("predictionOutcomes")
      .where("evaluatedAt", "==", null)
      .where("targetDate", "<", now)
      .limit(200) // Process in batches
      .get();
    
    if (pendingPredictions.empty) {
      console.log("No pending predictions to evaluate");
      return;
    }
    
    console.log(`Found ${pendingPredictions.size} predictions to evaluate`);
    
    // Group predictions by coin to minimize API calls
    const predictionsByCoin: Map<string, FirebaseFirestore.QueryDocumentSnapshot[]> = new Map();
    for (const doc of pendingPredictions.docs) {
      const coinId = doc.data().coinId;
      if (!predictionsByCoin.has(coinId)) {
        predictionsByCoin.set(coinId, []);
      }
      predictionsByCoin.get(coinId)!.push(doc);
    }
    
    // Fetch current prices - try Firestore first, then CoinGecko as fallback
    const coinIds = Array.from(predictionsByCoin.keys()).join(",");
    let priceData: Record<string, { usd: number }> = {};
    
    try {
      // RATE LIMIT FIX: Try Firestore coingeckoMarkets first
      const firestoreCG = await db.collection("marketData").doc("coingeckoMarkets").get();
      if (firestoreCG.exists) {
        const fsData = firestoreCG.data();
        if (Array.isArray(fsData?.coins)) {
          for (const coin of fsData.coins) {
            if (coin.id && coin.current_price) {
              priceData[coin.id] = { usd: coin.current_price };
            }
          }
          console.log(`[evaluatePredictionOutcomes] Got ${Object.keys(priceData).length} prices from Firestore`);
        }
      }
      
      // Fallback to CoinGecko API if Firestore didn't have enough prices
      if (Object.keys(priceData).length < predictionsByCoin.size) {
        const priceResponse = await fetchCoinGeckoTracked(
          `https://api.coingecko.com/api/v3/simple/price?ids=${coinIds}&vs_currencies=usd`,
          "evaluatePredictionOutcomes",
          "simple_price"
        );
        if (priceResponse.ok) {
          const apiPrices = await priceResponse.json();
          // Merge - API data takes precedence for freshness
          priceData = { ...priceData, ...apiPrices };
        }
      }
    } catch (error) {
      console.error("Failed to fetch prices:", error);
      // Continue with any prices we can get
    }
    
    // Evaluate each prediction
    const batch = db.batch();
    let evaluated = 0;
    let skipped = 0;
    
    for (const doc of pendingPredictions.docs) {
      const data = doc.data();
      const coinId = data.coinId;
      const actualPrice = priceData[coinId]?.usd;
      
      if (!actualPrice) {
        // Try using symbol as coinId (e.g., "btc" might need to be "bitcoin")
        const symbolToId: Record<string, string> = {
          btc: "bitcoin", eth: "ethereum", sol: "solana", xrp: "ripple",
          ada: "cardano", doge: "dogecoin", avax: "avalanche-2", link: "chainlink",
          dot: "polkadot", matic: "matic-network", shib: "shiba-inu", uni: "uniswap",
          ltc: "litecoin", bch: "bitcoin-cash", atom: "cosmos", fil: "filecoin",
          apt: "aptos", near: "near", op: "optimism", arb: "arbitrum",
        };
        const mappedId = symbolToId[coinId.toLowerCase()];
        const mappedPrice = mappedId ? priceData[mappedId]?.usd : undefined;
        
        if (!mappedPrice) {
          console.log(`Skipping ${data.symbol}: no price data available`);
          skipped++;
          continue;
        }
      }
      
      const price = actualPrice || priceData[coinId.toLowerCase()]?.usd;
      if (!price) {
        skipped++;
        continue;
      }
      
      // Calculate outcomes
      const priceAtPrediction = data.priceAtPrediction;
      const priceChangePercent = ((price - priceAtPrediction) / priceAtPrediction) * 100;
      
      // Determine actual direction
      let actualDirection: "bullish" | "bearish" | "neutral";
      if (priceChangePercent > 1) {
        actualDirection = "bullish";
      } else if (priceChangePercent < -1) {
        actualDirection = "bearish";
      } else {
        actualDirection = "neutral";
      }
      
      // Check if prediction was correct
      const predictedDirection = data.direction;
      const wasCorrect = predictedDirection === actualDirection ||
        (predictedDirection === "neutral" && Math.abs(priceChangePercent) <= 1);
      
      // Check if within predicted range
      const priceLow = data.priceRangeLow;
      const priceHigh = data.priceRangeHigh;
      const withinRange = (priceLow === null || priceChangePercent >= priceLow) &&
                         (priceHigh === null || priceChangePercent <= priceHigh);
      
      // Calculate price error (difference from predicted direction)
      const priceError = Math.abs(priceChangePercent - (data.confidence > 50 ? 
        (data.direction === "bullish" ? 5 : data.direction === "bearish" ? -5 : 0) : 0));
      
      // Update the document
      batch.update(doc.ref, {
        actualPrice: price,
        actualDirection,
        actualPriceChange: priceChangePercent,
        wasCorrect,
        withinRange,
        priceError,
        evaluatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      evaluated++;
    }
    
    if (evaluated > 0) {
      await batch.commit();
    }
    
    console.log(`Evaluated ${evaluated} predictions, skipped ${skipped}`);
    
    // Now update global accuracy metrics
    await updateGlobalAccuracyMetrics();
    
  } catch (error) {
    console.error("Error evaluating predictions:", error);
  }
});

/**
 * Update global accuracy metrics based on all evaluated predictions
 * Called after evaluation runs
 */
async function updateGlobalAccuracyMetrics(): Promise<void> {
  try {
    // Query all evaluated predictions
    const evaluatedPredictions = await db.collection("predictionOutcomes")
      .where("evaluatedAt", "!=", null)
      .get();
    
    if (evaluatedPredictions.empty) {
      console.log("No evaluated predictions for metrics");
      return;
    }
    
    // Calculate metrics
    let totalPredictions = 0;
    let directionsCorrect = 0;
    let withinRangeCount = 0;
    let totalPriceError = 0;
    
    const byTimeframe: Record<string, { total: number; correct: number }> = {};
    const byDirection: Record<string, { total: number; correct: number }> = {};
    const byConfidenceLevel: Record<string, { total: number; correct: number }> = {};
    
    for (const doc of evaluatedPredictions.docs) {
      const data = doc.data();
      
      totalPredictions++;
      
      if (data.wasCorrect) {
        directionsCorrect++;
      }
      
      if (data.withinRange) {
        withinRangeCount++;
      }
      
      if (data.priceError !== null && data.priceError !== undefined) {
        totalPriceError += Math.abs(data.priceError);
      }
      
      // By timeframe
      const tf = data.timeframe || "unknown";
      if (!byTimeframe[tf]) {
        byTimeframe[tf] = { total: 0, correct: 0 };
      }
      byTimeframe[tf].total++;
      if (data.wasCorrect) {
        byTimeframe[tf].correct++;
      }
      
      // By direction
      const dir = data.direction || "unknown";
      if (!byDirection[dir]) {
        byDirection[dir] = { total: 0, correct: 0 };
      }
      byDirection[dir].total++;
      if (data.wasCorrect) {
        byDirection[dir].correct++;
      }
      
      // By confidence level
      const confidence = data.confidence || 50;
      let confidenceLevel: string;
      if (confidence >= 70) {
        confidenceLevel = "high";
      } else if (confidence >= 45) {
        confidenceLevel = "medium";
      } else {
        confidenceLevel = "low";
      }
      if (!byConfidenceLevel[confidenceLevel]) {
        byConfidenceLevel[confidenceLevel] = { total: 0, correct: 0 };
      }
      byConfidenceLevel[confidenceLevel].total++;
      if (data.wasCorrect) {
        byConfidenceLevel[confidenceLevel].correct++;
      }
    }
    
    // Calculate percentages
    const directionAccuracyPercent = totalPredictions > 0 ?
      (directionsCorrect / totalPredictions) * 100 : 0;
    const rangeAccuracyPercent = totalPredictions > 0 ?
      (withinRangeCount / totalPredictions) * 100 : 0;
    const averageError = totalPredictions > 0 ?
      totalPriceError / totalPredictions : 0;
    
    // Calculate timeframe accuracy percentages
    const timeframeAccuracy: Record<string, number> = {};
    for (const [tf, stats] of Object.entries(byTimeframe)) {
      timeframeAccuracy[tf] = stats.total > 0 ? (stats.correct / stats.total) * 100 : 0;
    }
    
    // Calculate direction accuracy percentages
    const directionBreakdown: Record<string, number> = {};
    for (const [dir, stats] of Object.entries(byDirection)) {
      directionBreakdown[dir] = stats.total > 0 ? (stats.correct / stats.total) * 100 : 0;
    }
    
    // Calculate confidence level accuracy
    const confidenceAccuracy: Record<string, number> = {};
    for (const [level, stats] of Object.entries(byConfidenceLevel)) {
      confidenceAccuracy[level] = stats.total > 0 ? (stats.correct / stats.total) * 100 : 0;
    }
    
    // Store in Firestore
    await db.collection("globalAccuracyMetrics").doc("current").set({
      totalPredictions,
      directionsCorrect,
      withinRangeCount,
      directionAccuracyPercent,
      rangeAccuracyPercent,
      averageError,
      byTimeframe,
      byDirection,
      byConfidenceLevel,
      timeframeAccuracy,
      directionBreakdown,
      confidenceAccuracy,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log(`Updated global accuracy metrics: ${totalPredictions} predictions, ${directionAccuracyPercent.toFixed(1)}% direction accuracy`);
    
  } catch (error) {
    console.error("Error updating global accuracy metrics:", error);
  }
}

/**
 * Get global accuracy metrics (callable function for iOS app)
 * Returns the latest aggregated accuracy data
 */
export const getGlobalAccuracyMetrics = onCall({
  timeoutSeconds: 10,
  memory: "256MiB",
}, async () => {
  try {
    const metricsDoc = await db.collection("globalAccuracyMetrics").doc("current").get();
    
    if (!metricsDoc.exists) {
      // Return baseline metrics if no data yet
      return {
        totalPredictions: 0,
        directionAccuracyPercent: 50,
        rangeAccuracyPercent: 50,
        averageError: 3,
        timeframeAccuracy: {},
        directionBreakdown: {},
        confidenceAccuracy: {},
        hasData: false,
        lastUpdated: new Date().toISOString(),
      };
    }
    
    const data = metricsDoc.data()!;
    
    return {
      totalPredictions: data.totalPredictions,
      directionsCorrect: data.directionsCorrect,
      withinRangeCount: data.withinRangeCount,
      directionAccuracyPercent: data.directionAccuracyPercent,
      rangeAccuracyPercent: data.rangeAccuracyPercent,
      averageError: data.averageError,
      byTimeframe: data.byTimeframe,
      byDirection: data.byDirection,
      byConfidenceLevel: data.byConfidenceLevel,
      timeframeAccuracy: data.timeframeAccuracy,
      directionBreakdown: data.directionBreakdown,
      confidenceAccuracy: data.confidenceAccuracy,
      hasData: true,
      lastUpdated: data.lastUpdated?.toDate?.()?.toISOString() || new Date().toISOString(),
    };
  } catch (error) {
    throw safeError(error, "getGlobalAccuracyMetrics");
  }
});

// ============================================================================
// TECHNICALS PRE-WARMING & MULTI-SOURCE
// ============================================================================

/**
 * Pre-warm technicals summaries for top coins every 30 minutes
 * CryptoSage-exclusive: ensures fast responses with pre-computed advanced analysis
 */
export const prewarmTechnicalsSummary = onSchedule({
  schedule: "every 30 minutes",
  timeZone: "UTC",
  memory: "512MiB",
  timeoutSeconds: 300,
}, async () => {
  console.log("Pre-warming technicals summaries...");
  
  const topCoins = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "AVAX", "LINK", "DOT", "MATIC",
    "SHIB", "UNI", "LTC", "BCH", "ATOM", "FIL", "APT", "NEAR", "OP", "ARB"];
  const intervals = ["1h", "4h", "1d"];
  
  let successCount = 0;
  let errorCount = 0;
  
  for (const symbol of topCoins) {
    for (const interval of intervals) {
      try {
        const cacheKey = `technicals_cryptosage_${symbol}_${interval}`;
        
        // Fetch candles from Binance
        const candles = await fetchBinanceCandles(symbol, interval, 500);
        
        if (candles.length < 50) {
          console.log(`Skipping ${symbol}/${interval}: insufficient data (${candles.length} candles)`);
          continue;
        }
        
        // Compute CryptoSage enhanced summary
        const summary = computeTechnicalsSummary(candles);
        
        // Update the AI summary with actual symbol
        const aiSummary = generateAISummary({
          ...summary,
          divergences: summary.divergences,
          parabolicSar: summary.parabolicSar,
          supertrend: summary.supertrend,
        }, candles[candles.length - 1].close, symbol);
        
        // Cache in Firestore
        await db.collection("sharedAICache").doc(cacheKey).set({
          summary: { ...summary, aiSummary, source: "cryptosage" },
          symbol,
          interval,
          candleCount: candles.length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          prewarmed: true,
        });
        
        successCount++;
        
        // Small delay to avoid API rate limits
        await new Promise(resolve => setTimeout(resolve, 100));
      } catch (error) {
        console.error(`Error pre-warming ${symbol}/${interval}:`, error);
        errorCount++;
      }
    }
  }
  
  console.log(`Technicals pre-warming complete: ${successCount} success, ${errorCount} errors`);
});

/**
 * Get technicals from any source with shared caching
 * Routes CryptoSage, Coinbase, and Binance through Firebase for consistency
 */
export const getTechnicalsFromSource = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const data = request.data as { symbol?: string; interval?: string; source?: string };
  
  // Validate inputs
  const symbol = validateCoinSymbol(data.symbol);
  const interval = sanitizeString(data.interval || "1d", 10);
  const source = sanitizeString(data.source || "cryptosage", 20) as "cryptosage" | "coinbase" | "binance";
  
  if (!["cryptosage", "coinbase", "binance"].includes(source)) {
    throw new HttpsError("invalid-argument", "Invalid source. Must be cryptosage, coinbase, or binance");
  }
  
  // Rate limiting
  const clientIP = getClientIP(request);
  await checkRateLimit(clientIP, "publicMarket");
  
  const cacheKey = `technicals_${source}_${symbol}_${interval}`;
  const cacheRef = db.collection("sharedAICache").doc(cacheKey);
  const cacheTTL = CACHE_DURATIONS.technicalSummary;
  
  // Check cache first
  const cacheDoc = await cacheRef.get();
  if (cacheDoc.exists) {
    const cached = cacheDoc.data();
    if (cached && isCacheValid(cached.updatedAt, cacheTTL)) {
      console.log(`Cache hit: ${cacheKey}`);
      return { ...cached.summary, cached: true };
    }
  }
  
  // Request coalescing - try to acquire lock
  const lockKey = `technicals_fetch_${cacheKey}`;
  const lockRef = db.collection("_fetchLocks").doc(lockKey);
  
  let acquiredLock = false;
  try {
    await db.runTransaction(async (transaction) => {
      const lockDoc = await transaction.get(lockRef);
      if (lockDoc.exists) {
        const lockData = lockDoc.data();
        const lockAge = Date.now() - (lockData?.lockedAt?.toMillis() || 0);
        if (lockAge < FETCH_LOCK_DURATION) {
          // Someone else is fetching, wait for cache
          throw new Error("LOCK_EXISTS");
        }
      }
      // Acquire lock
      transaction.set(lockRef, {
        lockedAt: admin.firestore.FieldValue.serverTimestamp(),
        source,
        symbol,
        interval,
      });
      acquiredLock = true;
    });
  } catch (lockError: unknown) {
    if (lockError instanceof Error && lockError.message === "LOCK_EXISTS") {
      // Wait for the other request to populate cache
      for (let i = 0; i < 20; i++) {
        await new Promise(resolve => setTimeout(resolve, 500));
        const freshDoc = await cacheRef.get();
        if (freshDoc.exists) {
          const data = freshDoc.data();
          if (data && isCacheValid(data.updatedAt, cacheTTL)) {
            return { ...data.summary, cached: true, coalesced: true };
          }
        }
      }
      throw new HttpsError("deadline-exceeded", "Timed out waiting for technicals data");
    }
    throw lockError;
  }
  
  try {
    let summary: TechnicalsSummary;
    let candles;
    
    if (source === "cryptosage") {
      // CryptoSage: Use enhanced 30+ indicator analysis with Binance data
      candles = await fetchBinanceCandles(symbol, interval, 500);
      summary = computeTechnicalsSummary(candles);
      
      // Generate AI summary with actual symbol
      const aiSummary = generateAISummary({
        ...summary,
        divergences: summary.divergences,
        parabolicSar: summary.parabolicSar,
        supertrend: summary.supertrend,
      }, candles[candles.length - 1].close, symbol);
      
      summary = { ...summary, aiSummary, source: "cryptosage" };
    } else if (source === "coinbase") {
      // Coinbase: Basic 15 indicator analysis
      candles = await fetchCoinbaseCandles(symbol, interval, 300);
      summary = computeBasicTechnicalsSummary(candles, "coinbase");
    } else {
      // Binance: Basic 15 indicator analysis
      candles = await fetchBinanceCandles(symbol, interval, 500);
      summary = computeBasicTechnicalsSummary(candles, "binance");
    }
    
    // Cache the result
    await cacheRef.set({
      summary,
      symbol,
      interval,
      candleCount: candles.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    // Release lock
    await lockRef.delete();
    
    return { ...summary, cached: false };
  } catch (fetchError) {
    // Release lock on error
    if (acquiredLock) {
      await lockRef.delete().catch(() => {});
    }
    
    // Return stale cache if available
    if (cacheDoc.exists) {
      const stale = cacheDoc.data();
      if (stale?.summary) {
        console.log(`Returning stale cache for ${cacheKey} after fetch error`);
        return { ...stale.summary, cached: true, stale: true };
      }
    }
    
    console.error(`Error fetching technicals for ${source}/${symbol}/${interval}:`, fetchError);
    throw new HttpsError("internal", `Failed to fetch technicals from ${source}`);
  }
});

// ============================================================================
// HEALTH CHECK
// ============================================================================

/**
 * Health check endpoint for monitoring
 */
export const healthCheck = onRequest({
  timeoutSeconds: 10,
  memory: "128MiB",
}, async (req, res) => {
  try {
    // Quick Firestore connectivity test
    await db.collection("_health").doc("check").set({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    res.json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      version: "1.0.0",
    });
  } catch (error) {
    console.error("Health check failed:", error);
    res.status(500).json({
      status: "unhealthy",
      error: "Internal error",
      timestamp: new Date().toISOString(),
    });
  }
});

// ============================================================================
// WEB SEARCH (AI Research Capability)
// ============================================================================

/**
 * Perform a web search using Tavily API
 * Rate limited by subscription tier
 * 
 * Security: Rate limited, subscription-gated, audit logged
 */
export const webSearch = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
  secrets: ["TAVILY_API_KEY"],
}, async (request) => {
  const clientIP = getClientIP(request);
  const userId = await validateAuth(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, userId ? "userAI" : "publicAI");
    
    // Validate input
    const query = sanitizeString(request.data?.query, 500);
    if (!query || query.length < 2) {
      throw new HttpsError("invalid-argument", "Search query is required (2-500 characters)");
    }
    
    // Check subscription and daily limits
    let tier: "free" | "pro" | "premium" = "free";
    let dailyUsed = 0;
    
    if (userId) {
      const subscription = await verifySubscription(userId);
      tier = subscription.tier as "free" | "pro" | "premium";
      
      // Check daily usage
      const today = new Date().toISOString().split("T")[0];
      const usageRef = db.collection("userUsage").doc(`${userId}_${today}`);
      const usageDoc = await usageRef.get();
      dailyUsed = usageDoc.exists ? (usageDoc.data()?.webSearches || 0) : 0;
    }
    
    const limits = getTierLimits(tier);
    if (dailyUsed >= limits.dailyWebSearches) {
      throw new HttpsError(
        "resource-exhausted",
        `Daily web search limit reached (${limits.dailyWebSearches} for ${tier} tier). Upgrade for more searches.`
      );
    }
    
    // Call Tavily API
    const tavilyKey = process.env.TAVILY_API_KEY;
    if (!tavilyKey) {
      throw new HttpsError("failed-precondition", "Web search not configured");
    }
    
    const response = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        api_key: tavilyKey,
        query: query,
        search_depth: "basic",
        include_answer: true,
        include_raw_content: false,
        max_results: 5,
      }),
    });
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error("Tavily API error:", errorText);
      
      if (response.status === 401) {
        throw new HttpsError("failed-precondition", "Web search API configuration error");
      } else if (response.status === 429) {
        throw new HttpsError("resource-exhausted", "Web search temporarily unavailable. Please try again later.");
      }
      throw new HttpsError("internal", "Web search failed. Please try again.");
    }
    
    const searchResult = await response.json();
    
    // Update usage count
    if (userId) {
      const today = new Date().toISOString().split("T")[0];
      const usageRef = db.collection("userUsage").doc(`${userId}_${today}`);
      await usageRef.set({
        webSearches: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    
    // Log audit event
    await logAuditEvent("web_search", request, {
      query: query.substring(0, 100),
      tier,
      resultsCount: searchResult.results?.length || 0,
    });
    
    return {
      query: searchResult.query,
      answer: searchResult.answer,
      results: (searchResult.results || []).map((r: { title: string; url: string; content: string; published_date?: string }) => ({
        title: r.title,
        url: r.url,
        content: r.content,
        publishedDate: r.published_date,
      })),
      dailyUsed: dailyUsed + 1,
      dailyLimit: limits.dailyWebSearches,
    };
    
  } catch (error) {
    throw safeError(error, "webSearch");
  }
});

/**
 * Read article content from a URL
 * Rate limited by subscription tier
 */
export const readArticle = onCall({
  timeoutSeconds: 15,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  const userId = await validateAuth(request);
  
  try {
    // Rate limiting
    await checkRateLimit(clientIP, userId ? "userAI" : "publicAI");
    
    // Validate input
    const url = sanitizeString(request.data?.url, 2000);
    if (!url || !url.startsWith("http")) {
      throw new HttpsError("invalid-argument", "Valid URL is required");
    }
    
    // Check subscription and daily limits
    let tier: "free" | "pro" | "premium" = "free";
    let dailyUsed = 0;
    
    if (userId) {
      const subscription = await verifySubscription(userId);
      tier = subscription.tier as "free" | "pro" | "premium";
      
      // Check daily usage
      const today = new Date().toISOString().split("T")[0];
      const usageRef = db.collection("userUsage").doc(`${userId}_${today}`);
      const usageDoc = await usageRef.get();
      dailyUsed = usageDoc.exists ? (usageDoc.data()?.urlReads || 0) : 0;
    }
    
    const limits = getTierLimits(tier);
    if (dailyUsed >= limits.dailyUrlReads) {
      throw new HttpsError(
        "resource-exhausted",
        `Daily article read limit reached (${limits.dailyUrlReads} for ${tier} tier). Upgrade for more.`
      );
    }
    
    // Fetch the URL content
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);
    
    try {
      const response = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
          "Accept": "text/html,application/xhtml+xml",
        },
        signal: controller.signal,
      });
      
      clearTimeout(timeoutId);
      
      if (!response.ok) {
        throw new HttpsError("not-found", "Could not fetch article");
      }
      
      const html = await response.text();
      
      // Basic HTML content extraction
      let content = html;
      
      // Try to extract article content
      const articleMatch = content.match(/<article[^>]*>([\s\S]*?)<\/article>/i);
      if (articleMatch) {
        content = articleMatch[1];
      } else {
        const mainMatch = content.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
        if (mainMatch) {
          content = mainMatch[1];
        }
      }
      
      // Extract title
      const titleMatch = html.match(/<title[^>]*>([^<]*)<\/title>/i);
      const title = titleMatch ? titleMatch[1].trim() : "Article";
      
      // Strip HTML tags and clean up
      content = content
        .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
        .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
        .replace(/<nav[^>]*>[\s\S]*?<\/nav>/gi, "")
        .replace(/<header[^>]*>[\s\S]*?<\/header>/gi, "")
        .replace(/<footer[^>]*>[\s\S]*?<\/footer>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/g, " ")
        .replace(/&amp;/g, "&")
        .replace(/&lt;/g, "<")
        .replace(/&gt;/g, ">")
        .replace(/&quot;/g, '"')
        .replace(/\s+/g, " ")
        .trim()
        .substring(0, 4000); // Limit to 4000 chars
      
      // Update usage count
      if (userId) {
        const today = new Date().toISOString().split("T")[0];
        const usageRef = db.collection("userUsage").doc(`${userId}_${today}`);
        await usageRef.set({
          urlReads: admin.firestore.FieldValue.increment(1),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      
      // Log audit event
      await logAuditEvent("read_article", request, {
        url: url.substring(0, 100),
        tier,
      });
      
      return {
        title,
        url,
        content,
        dailyUsed: dailyUsed + 1,
        dailyLimit: limits.dailyUrlReads,
      };
      
    } catch (fetchError) {
      clearTimeout(timeoutId);
      if ((fetchError as Error).name === "AbortError") {
        throw new HttpsError("deadline-exceeded", "Article fetch timed out");
      }
      throw fetchError;
    }
    
  } catch (error) {
    throw safeError(error, "readArticle");
  }
});

// ============================================================================
// COIN IMAGE SYNC - Firebase Storage Management
// ============================================================================

/**
 * Helper function to fetch image from a URL and return as Buffer
 */
async function fetchImageBuffer(url: string): Promise<Buffer | null> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);
    
    const response = await fetch(url, {
      headers: {
        "Accept": "image/*,*/*;q=0.8",
        "User-Agent": "CryptoSage/1.0",
      },
      signal: controller.signal,
    });
    
    clearTimeout(timeoutId);
    
    if (!response.ok) {
      return null;
    }
    
    // Validate content type
    const contentType = response.headers.get("content-type") || "";
    if (!contentType.includes("image/") && !contentType.includes("application/octet-stream")) {
      return null;
    }
    
    const arrayBuffer = await response.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    
    // Validate minimum size (reject tiny error images)
    if (buffer.length < 100) {
      return null;
    }
    
    return buffer;
  } catch {
    return null;
  }
}

/**
 * Get image URL from various sources based on symbol
 */
function getImageUrls(symbol: string, coinGeckoImageUrl?: string): string[] {
  const lower = symbol.toLowerCase();
  const urls: string[] = [];
  
  // CoinGecko (if we have it from API)
  if (coinGeckoImageUrl) {
    urls.push(coinGeckoImageUrl);
  }
  
  // CoinCap CDN
  urls.push(`https://assets.coincap.io/assets/icons/${lower}@2x.png`);
  
  // CryptoIcons.org
  urls.push(`https://cryptoicons.org/api/icon/${lower}/200`);
  
  // SpotHQ GitHub
  urls.push(`https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/${lower}.png`);
  
  return urls;
}

/**
 * Upload image to Firebase Storage
 */
async function uploadCoinImage(symbol: string, imageBuffer: Buffer, sourceUrl: string): Promise<string | null> {
  try {
    const bucket = storage.bucket();
    const filePath = `${COIN_IMAGE_CONFIG.storagePath}/${symbol.toLowerCase()}.png`;
    const file = bucket.file(filePath);
    
    // Upload with metadata
    await file.save(imageBuffer, {
      metadata: {
        contentType: "image/png",
        cacheControl: "public, max-age=604800", // 7 days cache
        metadata: {
          source: sourceUrl,
          uploadedAt: new Date().toISOString(),
        },
      },
    });
    
    // Make publicly accessible
    await file.makePublic();
    
    // Return public URL
    const publicUrl = `https://storage.googleapis.com/${bucket.name}/${filePath}`;
    return publicUrl;
  } catch (error) {
    console.error(`Failed to upload image for ${symbol}:`, error);
    return null;
  }
}

/**
 * Sync a single coin's image to Firebase Storage
 */
async function syncCoinImageToStorage(
  symbol: string,
  coinGeckoImageUrl?: string
): Promise<{ success: boolean; url?: string; source?: string }> {
  const urls = getImageUrls(symbol, coinGeckoImageUrl);
  
  for (const url of urls) {
    const imageBuffer = await fetchImageBuffer(url);
    if (imageBuffer) {
      const publicUrl = await uploadCoinImage(symbol, imageBuffer, url);
      if (publicUrl) {
        // Update metadata in Firestore
        await db.collection("coinImageMeta").doc(symbol.toLowerCase()).set({
          symbol: symbol.toLowerCase(),
          storageUrl: publicUrl,
          sourceUrl: url,
          lastSynced: admin.firestore.FieldValue.serverTimestamp(),
          size: imageBuffer.length,
        });
        
        return { success: true, url: publicUrl, source: url };
      }
    }
  }
  
  return { success: false };
}

/**
 * Scheduled function to sync coin images to Firebase Storage
 * Runs every 6 hours to keep images fresh and add new coins
 */
export const syncCoinImages = onSchedule({
  schedule: "every 6 hours",
  timeoutSeconds: 540,  // 9 minutes max
  memory: "512MiB",
  region: "us-central1",
}, async () => {
  console.log("Starting scheduled coin image sync...");
  
  try {
    // RATE LIMIT FIX: Try Firestore first, then CoinGecko as fallback
    let coins: Array<{ symbol: string; image: string; market_cap_rank: number; }> = [];
    
    const firestoreCG = await db.collection("marketData").doc("coingeckoMarkets").get();
    if (firestoreCG.exists && Array.isArray(firestoreCG.data()?.coins)) {
      coins = firestoreCG.data()!.coins;
      console.log(`Using ${coins.length} coins from Firestore for image sync`);
    } else {
      // Fallback: fetch from CoinGecko API
      const response = await fetchCoinGeckoTracked(
        `https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=${COIN_IMAGE_CONFIG.maxCoinsToSync}&page=1&sparkline=false`,
        "syncCoinImages",
        "coins_markets"
      );
      
      if (!response.ok) {
        console.error("Failed to fetch coin list from CoinGecko:", response.status);
        return;
      }
      
      coins = await response.json();
      console.log(`Fetched ${coins.length} coins from CoinGecko API`);
    }
    
    // Check which coins need syncing
    const coinsToSync: Array<{ symbol: string; imageUrl: string }> = [];
    
    for (const coin of coins) {
      const metaDoc = await db.collection("coinImageMeta").doc(coin.symbol.toLowerCase()).get();
      
      if (!metaDoc.exists) {
        // New coin, needs sync
        coinsToSync.push({ symbol: coin.symbol, imageUrl: coin.image });
      } else {
        const data = metaDoc.data();
        const lastSynced = data?.lastSynced?.toMillis() || 0;
        const now = Date.now();
        
        // Re-sync if older than cache duration
        if (now - lastSynced > CACHE_DURATIONS.coinImage) {
          coinsToSync.push({ symbol: coin.symbol, imageUrl: coin.image });
        }
      }
    }
    
    console.log(`${coinsToSync.length} coins need syncing`);
    
    // Process in batches to avoid timeout
    let synced = 0;
    let failed = 0;
    
    for (let i = 0; i < coinsToSync.length; i += COIN_IMAGE_CONFIG.syncBatchSize) {
      const batch = coinsToSync.slice(i, i + COIN_IMAGE_CONFIG.syncBatchSize);
      
      const results = await Promise.all(
        batch.map(coin => syncCoinImageToStorage(coin.symbol, coin.imageUrl))
      );
      
      for (const result of results) {
        if (result.success) {
          synced++;
        } else {
          failed++;
        }
      }
      
      console.log(`Batch progress: ${i + batch.length}/${coinsToSync.length} (synced: ${synced}, failed: ${failed})`);
      
      // Small delay between batches to avoid rate limiting
      if (i + COIN_IMAGE_CONFIG.syncBatchSize < coinsToSync.length) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
    
    console.log(`Coin image sync complete. Synced: ${synced}, Failed: ${failed}`);
    
    // Log audit event
    await db.collection("systemLogs").add({
      type: "coinImageSync",
      coinsProcessed: coinsToSync.length,
      synced,
      failed,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    
  } catch (error) {
    console.error("Coin image sync failed:", error);
  }
});

/**
 * On-demand function to get a coin image URL
 * Returns Firebase Storage URL if available, triggers sync if not
 */
export const getCoinImage = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  try {
    // Validate input
    const symbol = sanitizeString(request.data?.symbol, 20)?.toLowerCase();
    if (!symbol || !validateCoinSymbol(symbol)) {
      throw new HttpsError("invalid-argument", "Valid coin symbol is required");
    }
    
    // Check if we have it in storage
    const metaDoc = await db.collection("coinImageMeta").doc(symbol).get();
    
    if (metaDoc.exists) {
      const data = metaDoc.data();
      const lastSynced = data?.lastSynced?.toMillis() || 0;
      const now = Date.now();
      
      // Return cached URL if still valid
      if (now - lastSynced < CACHE_DURATIONS.coinImage && data?.storageUrl) {
        return {
          url: data.storageUrl,
          source: "firebase-storage",
          cached: true,
        };
      }
    }
    
    // Try to sync this specific coin
    const coinGeckoImageUrl = request.data?.coinGeckoImageUrl;
    const result = await syncCoinImageToStorage(symbol, coinGeckoImageUrl);
    
    if (result.success && result.url) {
      return {
        url: result.url,
        source: "firebase-storage",
        cached: false,
      };
    }
    
    // Return fallback URLs if sync failed
    const fallbackUrls = getImageUrls(symbol);
    return {
      url: fallbackUrls[0],
      fallbackUrls,
      source: "external",
      cached: false,
    };
    
  } catch (error) {
    throw safeError(error, "getCoinImage");
  }
});

/**
 * Manual trigger to populate Firebase Storage with coin images
 * Use this for initial migration or to force a full resync
 */
export const populateCoinImages = onCall({
  timeoutSeconds: 540,  // 9 minutes
  memory: "1GiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limit this expensive operation
    await checkRateLimit(clientIP, "adminOnly");
    
    const count = validateNumber(request.data?.count, 1, 1000) || 500;
    const forceResync = request.data?.forceResync === true;
    
    console.log(`Starting manual coin image population (count: ${count}, forceResync: ${forceResync})`);
    
    // Fetch coins from CoinGecko (tracked)
    const response = await fetchCoinGeckoTracked(
      `https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=${count}&page=1&sparkline=false`,
      "populateCoinImages",
      "coins_markets"
    );
    
    if (!response.ok) {
      throw new HttpsError("internal", "Failed to fetch coin list");
    }
    
    const coins = await response.json() as Array<{
      symbol: string;
      image: string;
    }>;
    
    let synced = 0;
    let skipped = 0;
    let failed = 0;
    
    for (let i = 0; i < coins.length; i += COIN_IMAGE_CONFIG.syncBatchSize) {
      const batch = coins.slice(i, i + COIN_IMAGE_CONFIG.syncBatchSize);
      
      const results = await Promise.all(
        batch.map(async (coin) => {
          // Check if already synced (unless forcing)
          if (!forceResync) {
            const metaDoc = await db.collection("coinImageMeta").doc(coin.symbol.toLowerCase()).get();
            if (metaDoc.exists) {
              return { status: "skipped" };
            }
          }
          
          const result = await syncCoinImageToStorage(coin.symbol, coin.image);
          return { status: result.success ? "synced" : "failed" };
        })
      );
      
      for (const r of results) {
        if (r.status === "synced") synced++;
        else if (r.status === "skipped") skipped++;
        else failed++;
      }
      
      // Rate limit delay
      if (i + COIN_IMAGE_CONFIG.syncBatchSize < coins.length) {
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }
    
    // Log the operation
    await logAuditEvent("populateCoinImages", request, {
      count,
      forceResync,
      synced,
      skipped,
      failed,
    });
    
    return {
      message: "Coin image population complete",
      stats: { synced, skipped, failed, total: coins.length },
    };
    
  } catch (error) {
    throw safeError(error, "populateCoinImages");
  }
});

// ============================================================================
// WHALE TRACKING PROXY
// ============================================================================

// Cache durations for whale data
const WHALE_CACHE_DURATION = 60 * 1000; // 60 seconds - whale data changes frequently
const WHALE_PRICES_CACHE_DURATION = 60 * 1000; // 60 seconds for price lookups

// Known exchange addresses for labeling
const KNOWN_EXCHANGE_ADDRESSES: Record<string, string> = {
  // Ethereum
  "0xbe0eb53f46cd790cd13851d5eff43d12404d33e8": "Binance",
  "0xf977814e90da44bfa03b6295a0616a897441acec": "Binance",
  "0x28c6c06298d514db089934071355e5743bf21d60": "Binance",
  "0xdfd5293d8e347dfe59e90efd55b2956a1343963d": "Coinbase",
  "0x503828976d22510aad0201ac7ec88293211d23da": "Coinbase",
  "0x71660c4005ba85c37ccec55d0c4493e66fe775d3": "Coinbase",
  "0x66f820a414680b5bcda5eeca5dea238543f42054": "OKX",
  "0x2910543af39aba0cd09dbb2d50200b3e800a63d2": "Kraken",
  "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa": "Bitfinex",
  // Bitcoin
  "34xp4vrocgjym3xr7ycvpfhocnxv4twseo": "Binance",
  "3nxwenay9z8lc9jbiwymexpnefil6afp8v": "Coinbase",
};

// Whale transaction interface
interface WhaleTransaction {
  id: string;
  blockchain: string;
  symbol: string;
  amount: number;
  amountUSD: number;
  fromAddress: string;
  toAddress: string;
  hash: string;
  timestamp: number;
  transactionType: string;
  dataSource: string;
  fromLabel?: string;
  toLabel?: string;
}

/**
 * Helper to fetch current crypto prices with caching
 */
async function getCryptoPrices(): Promise<{ btc: number; eth: number; sol: number }> {
  const cacheKey = "crypto_prices";
  const cacheRef = db.collection("_cache").doc(cacheKey);
  
  try {
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, WHALE_PRICES_CACHE_DURATION)) {
        return { btc: data.btc, eth: data.eth, sol: data.sol };
      }
    }
    
    // RATE LIMIT FIX: Try Firestore first for whale prices
    const firestoreCG = await db.collection("marketData").doc("coingeckoMarkets").get();
    if (firestoreCG.exists && Array.isArray(firestoreCG.data()?.coins)) {
      const fsCoins = firestoreCG.data()!.coins;
      const btcCoin = fsCoins.find((c: {id: string}) => c.id === "bitcoin");
      const ethCoin = fsCoins.find((c: {id: string}) => c.id === "ethereum");
      const solCoin = fsCoins.find((c: {id: string}) => c.id === "solana");
      
      if (btcCoin?.current_price && ethCoin?.current_price) {
        const result = {
          btc: btcCoin.current_price,
          eth: ethCoin.current_price,
          sol: solCoin?.current_price || 150,
        };
        
        await cacheRef.set({
          ...result,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        return result;
      }
    }
    
    // Fallback: fetch from CoinGecko (tracked)
    const response = await fetchCoinGeckoTracked(
      "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd",
      "getWhalePrices",
      "simple_price"
    );
    
    if (!response.ok) {
      throw new Error(`CoinGecko API error: ${response.status}`);
    }
    
    const prices = await response.json();
    const result = {
      btc: prices.bitcoin?.usd || 95000,
      eth: prices.ethereum?.usd || 3300,
      sol: prices.solana?.usd || 150,
    };
    
    // Cache the prices
    await cacheRef.set({
      ...result,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    return result;
  } catch (error) {
    console.error("Failed to fetch crypto prices:", error);
    return { btc: 95000, eth: 3300, sol: 150 }; // Fallback prices
  }
}

/**
 * Fetch Ethereum whale transactions from Etherscan
 */
async function fetchEtherscanWhales(ethPrice: number, minAmountUSD: number): Promise<WhaleTransaction[]> {
  const transactions: WhaleTransaction[] = [];
  
  // Top whale addresses to monitor - expanded list
  const whaleAddresses = [
    "0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8", // Binance
    "0xf977814e90da44bfa03b6295a0616a897441acec", // Binance
    "0x28C6c06298d514Db089934071355E5743bf21d60", // Binance
    "0xDFd5293D8e347dFe59E90eFd55b2956a1343963d", // Coinbase
    "0x503828976D22510aad0201ac7EC88293211D23Da", // Coinbase
    "0x66f820a414680B5bcda5eECA5dea238543F42054", // OKX
    "0x2910543Af39abA0Cd09dBb2D50200b3E800A63D2", // Kraken
    "0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa", // Bitfinex
  ];
  
  for (const address of whaleAddresses.slice(0, 6)) { // Increased to 6 addresses for better coverage
    try {
      const url = `https://api.etherscan.io/v2/api?chainid=1&module=account&action=txlist&address=${address}&startblock=0&endblock=99999999&page=1&offset=20&sort=desc`;
      const response = await fetch(url);
      
      if (!response.ok) continue;
      
      const data = await response.json();
      if (data.status !== "1" || !Array.isArray(data.result)) continue;
      
      for (const tx of data.result) {
        const valueWei = parseFloat(tx.value || "0");
        if (valueWei <= 0) continue;
        
        const ethAmount = valueWei / 1e18;
        const usdValue = ethAmount * ethPrice;
        
        if (usdValue < minAmountUSD) continue;
        
        const fromLower = tx.from?.toLowerCase() || "";
        const toLower = tx.to?.toLowerCase() || "";
        
        let transactionType = "transfer";
        const fromIsExchange = !!KNOWN_EXCHANGE_ADDRESSES[fromLower];
        const toIsExchange = !!KNOWN_EXCHANGE_ADDRESSES[toLower];
        
        if (fromIsExchange && !toIsExchange) {
          transactionType = "exchangeWithdrawal";
        } else if (!fromIsExchange && toIsExchange) {
          transactionType = "exchangeDeposit";
        }
        
        transactions.push({
          id: tx.hash,
          blockchain: "ethereum",
          symbol: "ETH",
          amount: ethAmount,
          amountUSD: usdValue,
          fromAddress: tx.from || "",
          toAddress: tx.to || "",
          hash: tx.hash,
          timestamp: parseInt(tx.timeStamp || "0") * 1000,
          transactionType,
          dataSource: "etherscan",
          fromLabel: KNOWN_EXCHANGE_ADDRESSES[fromLower],
          toLabel: KNOWN_EXCHANGE_ADDRESSES[toLower],
        });
      }
      
      // Rate limit delay
      await new Promise(resolve => setTimeout(resolve, 250));
    } catch (error) {
      console.error(`Etherscan error for ${address}:`, error);
    }
  }
  
  return transactions;
}

/**
 * Fetch Ethereum whale transactions from Ethplorer (FREE API)
 * Ethplorer tracks large token transfers across Ethereum
 */
async function fetchEthplorerWhales(ethPrice: number, minAmountUSD: number): Promise<WhaleTransaction[]> {
  const transactions: WhaleTransaction[] = [];
  
  try {
    // Ethplorer API - Get recent large transfers (free tier)
    // Focus on top tokens for meaningful whale activity
    const topTokensURL = "https://api.ethplorer.io/getTop?apiKey=freekey&criteria=cap&limit=8";
    const topResponse = await fetch(topTokensURL);
    
    if (!topResponse.ok) {
      console.log(`Ethplorer top tokens returned ${topResponse.status}`);
      return [];
    }
    
    const topData = await topResponse.json();
    const tokens = topData.tokens || [];
    
    for (const token of tokens.slice(0, 5)) {
      const tokenAddress = token.address;
      if (!tokenAddress) continue;
      
      try {
        // Get recent large transfers for this token
        const transfersURL = `https://api.ethplorer.io/getTokenHistory/${tokenAddress}?apiKey=freekey&type=transfer&limit=15`;
        const transferResponse = await fetch(transfersURL);
        
        if (!transferResponse.ok) continue;
        
        const transferData = await transferResponse.json();
        const operations = transferData.operations || [];
        
        for (const op of operations.slice(0, 10)) {
          const value = op.value;
          const timestamp = op.timestamp;
          const from = op.from;
          const to = op.to;
          const txHash = op.transactionHash;
          
          if (!value || !txHash) continue;
          
          const tokenInfo = op.tokenInfo || {};
          const symbol = tokenInfo.symbol || "ETH";
          const decimals = parseInt(tokenInfo.decimals || "18", 10);
          const priceRate = tokenInfo.price?.rate || ethPrice;
          
          // Calculate amount with proper decimals
          const rawAmount = parseFloat(value) || 0;
          const amount = rawAmount / Math.pow(10, decimals);
          const usdValue = amount * priceRate;
          
          // Only include whale-sized transactions
          if (usdValue < minAmountUSD) continue;
          
          const fromLower = (from || "").toLowerCase();
          const toLower = (to || "").toLowerCase();
          
          let transactionType = "transfer";
          const fromIsExchange = !!KNOWN_EXCHANGE_ADDRESSES[fromLower];
          const toIsExchange = !!KNOWN_EXCHANGE_ADDRESSES[toLower];
          
          if (fromIsExchange && !toIsExchange) {
            transactionType = "exchangeWithdrawal";
          } else if (!fromIsExchange && toIsExchange) {
            transactionType = "exchangeDeposit";
          }
          
          transactions.push({
            id: `ethplorer_${txHash.substring(0, 16)}`,
            blockchain: "ethereum",
            symbol,
            amount,
            amountUSD: usdValue,
            fromAddress: from || "",
            toAddress: to || "",
            hash: txHash,
            timestamp: (timestamp || 0) * 1000,
            transactionType,
            dataSource: "ethplorer",
            fromLabel: KNOWN_EXCHANGE_ADDRESSES[fromLower],
            toLabel: KNOWN_EXCHANGE_ADDRESSES[toLower],
          });
        }
        
        // Rate limit delay
        await new Promise(resolve => setTimeout(resolve, 150));
      } catch (tokenError) {
        console.error(`Ethplorer token error for ${tokenAddress}:`, tokenError);
      }
    }
  } catch (error) {
    console.error("Ethplorer error:", error);
  }
  
  console.log(`Ethplorer returned ${transactions.length} whale transactions`);
  return transactions;
}

/**
 * Fetch Bitcoin whale transactions from Blockchair
 */
async function fetchBlockchairWhales(btcPrice: number, minAmountUSD: number): Promise<WhaleTransaction[]> {
  const transactions: WhaleTransaction[] = [];
  
  try {
    // Blockchair API for large BTC transactions (>1000 BTC output)
    const minSatoshis = Math.floor((minAmountUSD / btcPrice) * 100000000);
    const url = `https://api.blockchair.com/bitcoin/transactions?q=output_total(${minSatoshis}..)&s=time(desc)&limit=50`;
    
    const response = await fetch(url, {
      headers: { "Accept": "application/json" }
    });
    
    if (!response.ok) {
      console.log(`Blockchair returned ${response.status}`);
      return [];
    }
    
    const data = await response.json();
    
    if (!data.data || !Array.isArray(data.data)) {
      return [];
    }
    
    for (const tx of data.data.slice(0, 30)) {
      const btcAmount = (tx.output_total || 0) / 100000000;
      const usdValue = btcAmount * btcPrice;
      
      if (usdValue < minAmountUSD) continue;
      
      // Parse timestamp
      let timestamp = Date.now();
      if (tx.time) {
        const parsed = Date.parse(tx.time);
        if (!isNaN(parsed)) timestamp = parsed;
      }
      
      transactions.push({
        id: tx.hash,
        blockchain: "bitcoin",
        symbol: "BTC",
        amount: btcAmount,
        amountUSD: usdValue,
        fromAddress: "Multiple Inputs",
        toAddress: "Multiple Outputs",
        hash: tx.hash,
        timestamp,
        transactionType: "transfer",
        dataSource: "blockchair",
      });
    }
  } catch (error) {
    console.error("Blockchair error:", error);
  }
  
  return transactions;
}

/**
 * Fetch Solana whale transactions from Solscan
 */
async function fetchSolscanWhales(solPrice: number, minAmountUSD: number): Promise<WhaleTransaction[]> {
  const transactions: WhaleTransaction[] = [];
  
  // Expanded Solana whale addresses
  const solanaAddresses = [
    "9WzDXwBbmPdCBoccRSmN7fc1FS1VkPMiZbq1ampYP9xJ", // Binance
    "H8sMJSCQxfKiFTCfDR3DUMLPwcRbM61LGFJ8N4dK3WjS", // Coinbase
    "5tzFkiKscXHK5ZXCGbXZxdw7gTjjD1mBwuoFbhUvuAi9", // Exchange
    "GaBxu5TxgA9V4CgKeLHvKgGzYhYu5EATN7hjHDapjMNj", // Large whale
    "2AQdpHJ2JpcEgPiATUXjQxA8QmafFegfQwSLWSprPicm", // Kraken
    "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E", // Binance 2
  ];
  
  for (const address of solanaAddresses.slice(0, 5)) { // Increased to 5 addresses
    try {
      const url = `https://public-api.solscan.io/account/transactions?account=${address}&limit=15`;
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      });
      
      if (!response.ok) continue;
      
      const data = await response.json();
      if (!Array.isArray(data)) continue;
      
      for (const tx of data) {
        const lamports = tx.lamport || 0;
        const solAmount = lamports / 1e9;
        const usdValue = solAmount * solPrice;
        
        if (usdValue < minAmountUSD) continue;
        
        transactions.push({
          id: `sol_${tx.txHash?.substring(0, 16) || Date.now()}`,
          blockchain: "solana",
          symbol: "SOL",
          amount: solAmount,
          amountUSD: usdValue,
          fromAddress: tx.signer?.[0] || address,
          toAddress: address,
          hash: tx.txHash || "",
          timestamp: (tx.blockTime || Math.floor(Date.now() / 1000)) * 1000,
          transactionType: "transfer",
          dataSource: "solscan",
        });
      }
      
      await new Promise(resolve => setTimeout(resolve, 200));
    } catch (error) {
      console.error(`Solscan error for ${address}:`, error);
    }
  }
  
  return transactions;
}

/**
 * Deduplicate whale transactions from multiple API sources
 * Same transaction can appear from Etherscan AND Ethplorer, etc.
 */
function deduplicateWhaleTransactions(transactions: WhaleTransaction[]): WhaleTransaction[] {
  const seenHashes = new Set<string>();
  const uniqueTransactions: WhaleTransaction[] = [];
  
  // Data source priority (higher = preferred when duplicates found)
  const sourcePriority: Record<string, number> = {
    "whaleAlert": 100,    // Premium - most reliable
    "arkham": 90,         // Premium - detailed intelligence
    "blockchair": 70,     // Reliable Bitcoin data
    "etherscan": 60,      // Primary Ethereum source
    "ethplorer": 50,      // Secondary Ethereum (token transfers)
    "solscan": 60,        // Primary Solana source
    "helius": 50,         // Secondary Solana
  };
  
  // Sort by source priority (highest first) so we keep the best data
  const sorted = [...transactions].sort((a, b) => {
    const p1 = sourcePriority[a.dataSource] || 0;
    const p2 = sourcePriority[b.dataSource] || 0;
    return p2 - p1;
  });
  
  for (const tx of sorted) {
    // Normalize hash for comparison (some APIs add prefixes)
    const normalizedHash = (tx.hash || "")
      .replace(/^0x/i, "")
      .toLowerCase();
    
    if (!normalizedHash) continue;
    
    // Create a unique key combining blockchain + hash
    const uniqueKey = `${tx.blockchain}_${normalizedHash}`;
    
    if (!seenHashes.has(uniqueKey)) {
      seenHashes.add(uniqueKey);
      uniqueTransactions.push(tx);
    }
  }
  
  return uniqueTransactions;
}

/**
 * Get whale transactions with caching
 * Proxies Etherscan, Blockchair, and Solscan to prevent rate limiting
 */
export const getWhaleTransactions = onCall({
  timeoutSeconds: 60,
  memory: "512MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limit check
    await checkRateLimit(clientIP, "standard");
    
    // Parse parameters
    const minAmountUSD = validateNumber(request.data?.minAmountUSD, 100000, 100000000) || 100000;
    const blockchains = request.data?.blockchains || ["ethereum", "bitcoin", "solana"];
    
    // Check cache
    const cacheKey = `whale_transactions_${minAmountUSD}`;
    const cacheRef = db.collection("_whaleCache").doc(cacheKey);
    
    // Try to get from cache first
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, WHALE_CACHE_DURATION)) {
        return {
          transactions: data.transactions,
          cached: true,
          stale: false,
          updatedAt: data.updatedAt?.toDate()?.toISOString() || new Date().toISOString(),
        };
      }
    }
    
    // Request coalescing - check if another request is fetching
    const shouldFetch = await tryAcquireFetchLock(cacheKey);
    
    if (!shouldFetch) {
      // Wait for the other request to complete
      const waitResult = await waitForCachedData(cacheRef, WHALE_CACHE_DURATION, 10000);
      if (!waitResult.timedOut && waitResult.data) {
        return {
          transactions: waitResult.data.transactions,
          cached: true,
          coalesced: true,
          updatedAt: waitResult.data.updatedAt?.toDate()?.toISOString() || new Date().toISOString(),
        };
      }
    }
    
    try {
      // Fetch fresh data
      const prices = await getCryptoPrices();
      let allTransactions: WhaleTransaction[] = [];
      
      // Fetch from all enabled blockchains in parallel
      // UPGRADED: Multiple sources per blockchain for better coverage
      const fetchPromises: Promise<WhaleTransaction[]>[] = [];
      
      if (blockchains.includes("ethereum")) {
        // Primary: Etherscan (address monitoring)
        fetchPromises.push(fetchEtherscanWhales(prices.eth, minAmountUSD));
        // Secondary: Ethplorer (large token transfers - FREE)
        fetchPromises.push(fetchEthplorerWhales(prices.eth, minAmountUSD));
      }
      if (blockchains.includes("bitcoin")) {
        fetchPromises.push(fetchBlockchairWhales(prices.btc, minAmountUSD));
      }
      if (blockchains.includes("solana")) {
        fetchPromises.push(fetchSolscanWhales(prices.sol, minAmountUSD));
      }
      
      const results = await Promise.all(fetchPromises);
      for (const txs of results) {
        allTransactions = allTransactions.concat(txs);
      }
      
      // DEDUPLICATION: Remove duplicate transactions from multiple API sources
      // Same transaction might be returned by Etherscan AND Ethplorer
      const beforeDedup = allTransactions.length;
      allTransactions = deduplicateWhaleTransactions(allTransactions);
      const afterDedup = allTransactions.length;
      
      if (beforeDedup !== afterDedup) {
        console.log(`Deduplication: ${beforeDedup} → ${afterDedup} transactions (removed ${beforeDedup - afterDedup} duplicates)`);
      }
      
      // Sort by timestamp descending
      allTransactions.sort((a, b) => b.timestamp - a.timestamp);
      
      // Limit to reasonable number
      allTransactions = allTransactions.slice(0, 50);
      
      // Cache the results
      await cacheRef.set({
        transactions: allTransactions,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        minAmountUSD,
      });
      
      return {
        transactions: allTransactions,
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      if (shouldFetch) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getWhaleTransactions");
  }
});

// ============================================================================
// CRYPTO EVENTS / CALENDAR PROXY
// ============================================================================

const EVENTS_CACHE_DURATION = 2 * 60 * 60 * 1000; // 2 hours - events don't change frequently

interface CryptoEvent {
  id: string;
  title: string;
  date: string;
  category: string;
  impact: string;
  subtitle?: string;
  urlString?: string;
  coinSymbols: string[];
  source: string;
}

/**
 * Get known recurring events (FOMC, CPI, etc.)
 */
function getKnownRecurringEvents(): CryptoEvent[] {
  const now = new Date();
  const year = now.getFullYear();
  const events: CryptoEvent[] = [];
  
  // 2026 FOMC dates (Federal Reserve)
  const fomcDates = [
    { month: 1, day: 29 }, { month: 3, day: 18 }, { month: 5, day: 6 },
    { month: 6, day: 17 }, { month: 7, day: 29 }, { month: 9, day: 16 },
    { month: 11, day: 4 }, { month: 12, day: 16 }
  ];
  
  for (const { month, day } of fomcDates) {
    const date = new Date(year, month - 1, day);
    if (date > now) {
      events.push({
        id: `fomc_${year}_${month}_${day}`,
        title: "FOMC Meeting",
        date: date.toISOString(),
        category: "macro",
        impact: "high",
        subtitle: "Federal Reserve interest rate decision",
        urlString: "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm",
        coinSymbols: [],
        source: "federal_reserve",
      });
    }
  }
  
  // CPI release dates (typically 10th-14th of each month)
  for (let monthOffset = 0; monthOffset < 6; monthOffset++) {
    const cpiDate = new Date(year, now.getMonth() + monthOffset, 12, 8, 30);
    if (cpiDate > now) {
      events.push({
        id: `cpi_${cpiDate.getFullYear()}_${cpiDate.getMonth() + 1}`,
        title: "CPI Release",
        date: cpiDate.toISOString(),
        category: "macro",
        impact: "high",
        subtitle: "US Consumer Price Index data",
        urlString: "https://www.bls.gov/cpi/",
        coinSymbols: [],
        source: "bls",
      });
    }
  }
  
  // Bitcoin halving (April 2028)
  const btcHalving = new Date(2028, 3, 15);
  if (btcHalving > now) {
    events.push({
      id: "btc_halving_2028",
      title: "Bitcoin Halving",
      date: btcHalving.toISOString(),
      category: "onchain",
      impact: "high",
      subtitle: "Block reward reduces from 3.125 to 1.5625 BTC",
      urlString: "https://www.bitcoinblockhalf.com/",
      coinSymbols: ["BTC"],
      source: "blockchain",
    });
  }
  
  return events;
}

/**
 * Fetch events from CoinMarketCal API (if API key is configured)
 */
async function fetchCoinMarketCalEvents(): Promise<CryptoEvent[]> {
  const apiKey = process.env.COINMARKETCAL_API_KEY;
  if (!apiKey) {
    console.log("CoinMarketCal API key not configured, using fallback events");
    return [];
  }
  
  try {
    const now = new Date();
    const endDate = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000); // 90 days ahead
    
    const formatDate = (d: Date) => `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}/${d.getFullYear()}`;
    
    const url = `https://developers.coinmarketcal.com/v1/events?max=50&dateRangeStart=${formatDate(now)}&dateRangeEnd=${formatDate(endDate)}&sortBy=date_event`;
    
    const response = await fetch(url, {
      headers: {
        "Accept": "application/json",
        "x-api-key": apiKey,
      }
    });
    
    if (!response.ok) {
      console.log(`CoinMarketCal API error: ${response.status}`);
      return [];
    }
    
    const data = await response.json();
    if (!data.body || !Array.isArray(data.body)) {
      return [];
    }
    
    return data.body.map((event: any) => {
      const title = event.title?.en || "Unknown Event";
      const dateStr = event.date_event;
      let date = new Date().toISOString();
      
      // Parse date
      if (dateStr) {
        const parsed = Date.parse(dateStr);
        if (!isNaN(parsed)) {
          date = new Date(parsed).toISOString();
        }
      }
      
      // Categorize event
      const categories = event.categories?.map((c: any) => c.name?.toLowerCase() || "") || [];
      const titleLower = title.toLowerCase();
      
      let category = "onchain";
      if (["fork", "upgrade", "mainnet", "halving", "unlock"].some(k => titleLower.includes(k) || categories.includes(k))) {
        category = "onchain";
      } else if (["listing", "conference", "summit", "partnership"].some(k => titleLower.includes(k) || categories.includes(k))) {
        category = "exchange";
      }
      
      // Estimate impact
      let impact = "medium";
      const coins = event.coins?.map((c: any) => c.symbol?.toUpperCase() || "") || [];
      const majorCoins = ["BTC", "ETH", "SOL", "BNB", "XRP"];
      
      if (["halving", "fork", "mainnet"].some(k => titleLower.includes(k)) || 
          coins.some((c: string) => majorCoins.includes(c))) {
        impact = "high";
      }
      
      return {
        id: `cmc_${event.id || Date.now()}`,
        title,
        date,
        category,
        impact,
        subtitle: event.description?.en?.substring(0, 100),
        urlString: event.source || event.proof,
        coinSymbols: coins,
        source: "coinmarketcal",
      };
    });
  } catch (error) {
    console.error("CoinMarketCal fetch error:", error);
    return [];
  }
}

/**
 * Get upcoming crypto events with caching
 * Combines CoinMarketCal data with known recurring events
 */
export const getUpcomingEvents = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    // Rate limit
    await checkRateLimit(clientIP, "standard");
    
    const cacheKey = "upcoming_events";
    const cacheRef = db.collection("_eventsCache").doc(cacheKey);
    
    // Check cache
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, EVENTS_CACHE_DURATION)) {
        return {
          events: data.events,
          cached: true,
          stale: false,
          updatedAt: data.updatedAt?.toDate()?.toISOString() || new Date().toISOString(),
        };
      }
    }
    
    // Request coalescing
    const shouldFetch = await tryAcquireFetchLock(cacheKey);
    
    if (!shouldFetch) {
      const waitResult = await waitForCachedData(cacheRef, EVENTS_CACHE_DURATION, 8000);
      if (!waitResult.timedOut && waitResult.data) {
        return {
          events: waitResult.data.events,
          cached: true,
          coalesced: true,
          updatedAt: waitResult.data.updatedAt?.toDate()?.toISOString() || new Date().toISOString(),
        };
      }
    }
    
    try {
      // Fetch events from multiple sources
      const [coinMarketCalEvents] = await Promise.all([
        fetchCoinMarketCalEvents(),
      ]);
      
      // Get known recurring events
      const recurringEvents = getKnownRecurringEvents();
      
      // Combine and deduplicate
      const allEvents: CryptoEvent[] = [...coinMarketCalEvents, ...recurringEvents];
      
      // Sort by date
      allEvents.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
      
      // Cache the results
      await cacheRef.set({
        events: allEvents.slice(0, 50),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      
      return {
        events: allEvents.slice(0, 50),
        cached: false,
        updatedAt: new Date().toISOString(),
      };
    } finally {
      if (shouldFetch) {
        await releaseFetchLock(cacheKey);
      }
    }
  } catch (error) {
    throw safeError(error, "getUpcomingEvents");
  }
});

// ============================================================================
// LEADERBOARD DATA (Shared Demo + User Data)
// ============================================================================

const LEADERBOARD_CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

/**
 * Get leaderboard data with caching
 * Returns demo entries plus any real user submissions
 */
export const getLeaderboard = onCall({
  timeoutSeconds: 30,
  memory: "256MiB",
}, async (request) => {
  const clientIP = getClientIP(request);
  
  try {
    await checkRateLimit(clientIP, "standard");
    
    const category = sanitizeString(request.data?.category, 20) || "pnl";
    const period = sanitizeString(request.data?.period, 20) || "month";
    const tradingMode = sanitizeString(request.data?.tradingMode, 10) || "paper";
    const limit = validateNumber(request.data?.limit, 1, 100) || 50;
    
    const cacheKey = `leaderboard_${tradingMode}_${category}_${period}`;
    const cacheRef = db.collection("_leaderboardCache").doc(cacheKey);
    
    // Check cache
    const cached = await cacheRef.get();
    if (cached.exists) {
      const data = cached.data();
      if (data && isCacheValid(data.updatedAt, LEADERBOARD_CACHE_DURATION)) {
        return {
          entries: data.entries?.slice(0, limit) || [],
          cached: true,
          updatedAt: data.updatedAt?.toDate()?.toISOString() || new Date().toISOString(),
        };
      }
    }
    
    // For now, return empty - real leaderboard would aggregate from user submissions
    // This is a placeholder for future implementation
    // Demo data is generated client-side for privacy
    
    return {
      entries: [],
      cached: false,
      message: "Leaderboard entries are generated client-side for privacy",
      updatedAt: new Date().toISOString(),
    };
  } catch (error) {
    throw safeError(error, "getLeaderboard");
  }
});

// ============================================================================
// SMART MARKET ALERT DIGEST (Server-Side — eliminates per-user AI calls)
// ============================================================================

/**
 * Evaluate market conditions every 5 minutes and write an alert digest to Firestore.
 *
 * Architecture:
 * - Template-based notification writing for all signals (ZERO AI calls in normal operation).
 * - AI is only used when 3+ high-severity signals occur simultaneously and need synthesis.
 *   In practice this means AI is called maybe a few times per MONTH, not per day.
 * - Provider priority: DeepSeek ($0.28/1M tokens) → OpenRouter Free ($0) → OpenAI (last resort).
 * - Each iOS client listens to marketData/alertDigest via Firestore snapshot listener.
 * - Client locally matches signals to the user's holdings and sends local notifications.
 *
 * Cost comparison:
 * - Before: N users × 12 scans/hour = 12N AI calls/hour
 * - After:  ~0 AI calls/hour (templates handle 99%+ of scenarios)
 */
export const evaluateMarketAlerts = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "UTC",
  memory: "256MiB",
  timeoutSeconds: 55,
}, async () => {
  const TAG = "[evaluateMarketAlerts]";
  console.log(`${TAG} Starting market alert evaluation...`);

  try {
    // ── 1. Gather market data from Firestore (already synced by other functions) ──

    const [heatmapDoc, coingeckoDoc, globalDoc, newsDoc, prevDigestDoc] = await Promise.all([
      db.collection("marketData").doc("heatmap").get(),
      db.collection("marketData").doc("coingeckoMarkets").get(),
      db.collection("marketData").doc("globalStats").get(),
      db.collection("marketData").doc("news").get(),
      db.collection("marketData").doc("alertDigestPrevious").get(),
    ]);

    // ── BTC price & change from Binance heatmap ──
    const heatmapData = heatmapDoc.exists ? heatmapDoc.data() : null;
    const btcTicker = heatmapData?.tickers?.BTC;
    const btcPrice: number = btcTicker?.price ?? 0;
    const btcChange24h: number = btcTicker?.change24h ?? 0;
    const btcChange1h: number = btcTicker?.change1h ?? 0;

    // ── Global stats from CoinGecko ──
    const globalData = globalDoc.exists ? globalDoc.data() : null;
    const globalMarketCap: number = globalData?.totalMarketCap ?? 0;
    const globalChange24h: number = globalData?.marketCapChangePercentage24hUsd ?? 0;
    const fearGreedValue: number = globalData?.fearGreedValue ?? 0;
    const fearGreedLabel: string = globalData?.fearGreedClassification ?? "N/A";
    const btcDominance: number = globalData?.btcDominance ?? 0;

    // ── CoinGecko coins for top movers ──
    const coingeckoData = coingeckoDoc.exists ? coingeckoDoc.data() : null;
    const coins: Array<{
      symbol: string;
      current_price?: number;
      price_change_percentage_1h_in_currency?: number;
      price_change_percentage_24h_in_currency?: number;
      price_change_percentage_24h?: number;
    }> = coingeckoData?.coins ?? [];

    // ── Find top movers (>5% hourly change) ──
    const topMovers = coins
      .filter(c => {
        const h1 = c.price_change_percentage_1h_in_currency;
        return h1 !== undefined && h1 !== null && isFinite(h1) && Math.abs(h1) > 5;
      })
      .sort((a, b) => Math.abs(b.price_change_percentage_1h_in_currency ?? 0) - Math.abs(a.price_change_percentage_1h_in_currency ?? 0))
      .slice(0, 10)
      .map(c => ({
        symbol: (c.symbol || "").toUpperCase(),
        change1h: c.price_change_percentage_1h_in_currency ?? 0,
        price: c.current_price ?? 0,
      }));

    // ── News headlines (from last 30 min) ──
    const newsData = newsDoc.exists ? newsDoc.data() : null;
    const articles: Array<{
      title: string;
      source: string;
      publishedAt: string;
      categories?: string;
    }> = newsData?.articles ?? [];

    const thirtyMinAgo = Date.now() - 30 * 60 * 1000;
    const recentArticles = articles.filter(a => {
      const ts = new Date(a.publishedAt).getTime();
      return ts > thirtyMinAgo;
    }).slice(0, 5);

    // ── Build market snapshot ──
    const marketSnapshot = {
      btcPrice,
      btcChange1h,
      btcChange24h,
      globalMarketCap,
      globalChange24h,
      fearGreedValue,
      fearGreedLabel,
      btcDominance,
    };

    // ── 2. Load previous digest and detect threshold crossings ──

    const prevData = prevDigestDoc.exists ? prevDigestDoc.data() : null;
    const prevFearGreed: number = prevData?.marketSnapshot?.fearGreedValue ?? fearGreedValue;
    const prevBtcPrice: number = prevData?.marketSnapshot?.btcPrice ?? btcPrice;

    interface RawSignal {
      type: string;
      severity: "low" | "medium" | "high";
      affectedSymbols: string[];
      changePercent: number;
      description: string;
    }

    const rawSignals: RawSignal[] = [];

    // BTC major move (≥3.5% hourly)
    if (Math.abs(btcChange1h) >= 3.5) {
      const dir = btcChange1h > 0 ? "surged" : "dropped";
      rawSignals.push({
        type: "btcMajorMove",
        severity: Math.abs(btcChange1h) >= 7 ? "high" : "medium",
        affectedSymbols: ["BTC"],
        changePercent: btcChange1h,
        description: `Bitcoin ${dir} ${Math.abs(btcChange1h).toFixed(1)}% in the last hour to $${btcPrice.toLocaleString()}.`,
      });
    }

    // Global market shift (≥3% daily)
    if (Math.abs(globalChange24h) >= 3) {
      const dir = globalChange24h > 0 ? "up" : "down";
      rawSignals.push({
        type: "marketWideMove",
        severity: Math.abs(globalChange24h) >= 5 ? "high" : "medium",
        affectedSymbols: [],
        changePercent: globalChange24h,
        description: `The crypto market is ${dir} ${Math.abs(globalChange24h).toFixed(1)}% in 24h (total cap: $${(globalMarketCap / 1e12).toFixed(2)}T).`,
      });
    }

    // Sentiment shift (Fear & Greed ≥12 points from previous)
    const sentimentDelta = fearGreedValue - prevFearGreed;
    if (Math.abs(sentimentDelta) >= 12) {
      const dir = sentimentDelta > 0 ? "jumped up" : "dropped";
      rawSignals.push({
        type: "sentimentShift",
        severity: Math.abs(sentimentDelta) >= 20 ? "high" : "medium",
        affectedSymbols: [],
        changePercent: sentimentDelta,
        description: `Fear & Greed Index ${dir} ${Math.abs(sentimentDelta)} points to ${fearGreedValue}/100 (${fearGreedLabel}).`,
      });
    }

    // Individual coin major movers (>5% hourly — from topMovers)
    for (const mover of topMovers) {
      const dir = mover.change1h > 0 ? "up" : "down";
      rawSignals.push({
        type: mover.change1h > 0 ? "largeGain" : "largeDrop",
        severity: Math.abs(mover.change1h) >= 10 ? "high" : "medium",
        affectedSymbols: [mover.symbol],
        changePercent: mover.change1h,
        description: `${mover.symbol} is ${dir} ${Math.abs(mover.change1h).toFixed(1)}% in the last hour ($${mover.price.toLocaleString()}).`,
      });
    }

    // BTC significant price movement from previous digest (>3.5%)
    if (prevBtcPrice > 0 && btcPrice > 0) {
      const btcPctFromPrev = ((btcPrice - prevBtcPrice) / prevBtcPrice) * 100;
      if (Math.abs(btcPctFromPrev) >= 3.5 && !rawSignals.some(s => s.type === "btcMajorMove")) {
        const dir = btcPctFromPrev > 0 ? "up" : "down";
        rawSignals.push({
          type: "btcMajorMove",
          severity: Math.abs(btcPctFromPrev) >= 7 ? "high" : "medium",
          affectedSymbols: ["BTC"],
          changePercent: btcPctFromPrev,
          description: `Bitcoin moved ${dir} ${Math.abs(btcPctFromPrev).toFixed(1)}% since the last check ($${btcPrice.toLocaleString()}).`,
        });
      }
    }

    // ── Breaking news detection (keywords) ──
    const breakingKeywords = ["hack", "crash", "sec ", "regulation", "etf", "ban", "fraud", "arrest", "exploit", "emergency"];
    const breakingNews: Array<{ title: string; source: string; relevantSymbols: string[] }> = [];

    for (const article of recentArticles) {
      const titleLower = (article.title || "").toLowerCase();
      const isBreaking = breakingKeywords.some(kw => titleLower.includes(kw));
      if (isBreaking) {
        // Extract relevant symbols from the headline
        const relevantSymbols: string[] = [];
        const commonSymbols = ["BTC", "ETH", "SOL", "XRP", "ADA", "DOGE", "DOT", "MATIC", "AVAX", "LINK", "UNI", "ATOM", "BNB", "LTC"];
        for (const sym of commonSymbols) {
          if (titleLower.includes(sym.toLowerCase())) {
            relevantSymbols.push(sym);
          }
        }
        // Check for full names too
        if (titleLower.includes("bitcoin")) relevantSymbols.push("BTC");
        if (titleLower.includes("ethereum") || titleLower.includes("ether")) relevantSymbols.push("ETH");
        if (titleLower.includes("solana")) relevantSymbols.push("SOL");
        if (titleLower.includes("ripple")) relevantSymbols.push("XRP");

        breakingNews.push({
          title: article.title,
          source: article.source || "Unknown",
          relevantSymbols: [...new Set(relevantSymbols)],
        });

        if (!rawSignals.some(s => s.type === "breakingNews")) {
          rawSignals.push({
            type: "breakingNews",
            severity: "medium",
            affectedSymbols: [...new Set(relevantSymbols)],
            changePercent: 0,
            description: `Breaking news: "${article.title}" (${article.source}).`,
          });
        }
      }
    }

    // ── 3. Generate notification text — TEMPLATES by default, AI only for rare multi-signal events ──
    //
    // COST OPTIMIZATION: Writing "BTC dropped 5%" doesn't need an AI model.
    // Templates handle 99%+ of cases at $0 cost. AI is only invoked when 3+
    // high-severity signals occur simultaneously and benefit from synthesis
    // (e.g., BTC crash + sentiment shift + breaking news → one coherent alert).
    // In practice, that's maybe a few times per month.

    interface AlertSignal {
      type: string;
      severity: "low" | "medium" | "high";
      affectedSymbols: string[];
      changePercent: number;
      title: string;
      summary: string;
    }

    const sanitizeSymbols = (symbols: string[]): string[] => {
      return [...new Set(
        symbols
          .map((s) => (s || "").trim().toUpperCase())
          .filter((s) => /^[A-Z0-9]{2,12}$/.test(s))
      )].slice(0, 20);
    };

    // Template-based title/summary generator (instant, free)
    function generateTemplate(raw: RawSignal): { title: string; summary: string } {
      const pct = Math.abs(raw.changePercent).toFixed(1);

      switch (raw.type) {
        case "btcMajorMove": {
          const dir = raw.changePercent > 0 ? "up" : "down";
          return {
            title: `BTC ${dir} ${pct}% — $${btcPrice.toLocaleString()}`,
            summary: `Bitcoin moved ${dir} ${pct}% recently. The broader market is ${globalChange24h >= 0 ? "up" : "down"} ${Math.abs(globalChange24h).toFixed(1)}% in 24h. Sentiment: ${fearGreedLabel} (${fearGreedValue}/100).`,
          };
        }
        case "marketWideMove": {
          const dir = raw.changePercent > 0 ? "up" : "down";
          return {
            title: `Crypto market ${dir} ${pct}% in 24h`,
            summary: `Total market cap is ${dir} to $${(globalMarketCap / 1e12).toFixed(2)}T. BTC at $${btcPrice.toLocaleString()} (${btcChange24h >= 0 ? "+" : ""}${btcChange24h.toFixed(1)}% 24h). Sentiment: ${fearGreedLabel}.`,
          };
        }
        case "sentimentShift": {
          const dir = raw.changePercent > 0 ? "jumped to" : "fell to";
          return {
            title: `Sentiment ${dir} ${fearGreedValue}/100 (${fearGreedLabel})`,
            summary: `The Fear & Greed Index shifted ${Math.abs(raw.changePercent).toFixed(0)} points. This often signals a change in market direction. BTC is at $${btcPrice.toLocaleString()}.`,
          };
        }
        case "largeDrop": {
          const sym = raw.affectedSymbols[0] || "?";
          return {
            title: `${sym} down ${pct}% in the last hour`,
            summary: raw.description,
          };
        }
        case "largeGain": {
          const sym = raw.affectedSymbols[0] || "?";
          return {
            title: `${sym} up ${pct}% in the last hour`,
            summary: raw.description,
          };
        }
        case "breakingNews":
          return {
            title: "Breaking crypto news",
            summary: raw.description,
          };
        default:
          return {
            title: raw.description.substring(0, 60),
            summary: raw.description,
          };
      }
    }

    let signals: AlertSignal[] = [];

    if (rawSignals.length > 0) {
      // Count how many HIGH-severity signals there are
      const highSeverityCount = rawSignals.filter(s => s.severity === "high").length;

      // SMART AI DECISION: Only call AI when 3+ high-severity signals need synthesizing.
      // This is extremely rare (major crash + sentiment reversal + breaking news all at once).
      // Normal threshold crossings (single events) use free instant templates.
      const needsAI = highSeverityCount >= 3;

      if (needsAI) {
        console.log(`${TAG} ${rawSignals.length} signals (${highSeverityCount} high-severity) — rare multi-signal event, using AI for synthesis.`);

        try {
          const signalDescriptions = rawSignals.map((s, i) => `[${i + 1}] ${s.description}`).join("\n");

          const aiResult = await callAIWithFallback({
            messages: [
              {
                role: "system",
                content: "You are a crypto market alert writer. Write one concise push notification that synthesizes multiple simultaneous events. Be specific with numbers. No greetings, no filler. Output JSON only.",
              },
              {
                role: "user",
                content: `Multiple significant market events are happening simultaneously. Write ONE synthesized alert that covers the key points. Return JSON: {"title": "≤60 chars", "summary": "2-3 sentences max"}.

EVENTS:
${signalDescriptions}

CONTEXT: BTC $${btcPrice.toLocaleString()}, Market $${(globalMarketCap / 1e12).toFixed(2)}T, F&G ${fearGreedValue}/100`,
              },
            ],
            max_tokens: 200,
            temperature: 0.3,
            response_format: { type: "json_object" },
            functionName: "evaluateMarketAlerts",
          });

          try {
            const parsed = JSON.parse(aiResult.content);
            const synthTitle = parsed.title || "Multiple market events";
            const synthSummary = parsed.summary || rawSignals.map(s => s.description).join(" ");

            // Create ONE synthesized signal + individual template signals
            signals.push({
              type: "marketWideMove",
              severity: "high",
              affectedSymbols: sanitizeSymbols(rawSignals.flatMap(s => s.affectedSymbols)),
              changePercent: rawSignals[0].changePercent,
              title: synthTitle,
              summary: synthSummary,
            });

            console.log(`${TAG} AI synthesized ${rawSignals.length} signals into 1 alert (provider: ${aiResult.provider}, tokens: ${aiResult.tokens}).`);
          } catch {
            // Parse failed — fall through to templates
            console.warn(`${TAG} AI parse failed, falling back to templates.`);
            signals = rawSignals.map(raw => ({ ...generateTemplate(raw), type: raw.type, severity: raw.severity, affectedSymbols: sanitizeSymbols(raw.affectedSymbols), changePercent: raw.changePercent }));
          }
        } catch (aiErr) {
          console.warn(`${TAG} AI call failed (${(aiErr as Error).message}), using templates.`);
          signals = rawSignals.map(raw => ({ ...generateTemplate(raw), type: raw.type, severity: raw.severity, affectedSymbols: sanitizeSymbols(raw.affectedSymbols), changePercent: raw.changePercent }));
        }
      } else {
        // NORMAL PATH: Use instant templates — zero AI cost
        console.log(`${TAG} ${rawSignals.length} signal(s) detected — using templates (zero AI cost).`);
        signals = rawSignals.map(raw => ({
          type: raw.type,
          severity: raw.severity,
          affectedSymbols: sanitizeSymbols(raw.affectedSymbols),
          changePercent: raw.changePercent,
          ...generateTemplate(raw),
        }));
      }
    } else {
      console.log(`${TAG} No threshold crossings — writing snapshot only.`);
    }

    // ── 4. Write digest to Firestore ──

    const digest = {
      timestamp: new Date().toISOString(),
      signals,
      marketSnapshot,
      topMovers,
      breakingNews,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db.collection("marketData").doc("alertDigest").set(digest);

    // Save current snapshot as "previous" for next comparison
    await db.collection("marketData").doc("alertDigestPrevious").set({
      marketSnapshot,
      timestamp: new Date().toISOString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // ── 5. Send push notifications for high-severity signals ──

    // Only send notifications for high-severity signals to avoid spam
    const highSeveritySignals = signals.filter(s => s.severity === "high");

    if (highSeveritySignals.length > 0) {
      console.log(`${TAG} Sending push notifications for ${highSeveritySignals.length} high-severity signal(s)`);

      // Send notification for each high-severity signal
      for (const signal of highSeveritySignals) {
        try {
          // Prepare notification payload
          const notificationTitle = signal.title || "Market Alert";
          const notificationBody = signal.summary || "Significant market movement detected";

          // Call the sendMarketAlertNotification function (internal call)
          await sendMarketAlertToAllUsers(
            notificationTitle,
            notificationBody,
            "high",
            signal.affectedSymbols || []
          );

          console.log(`${TAG} Sent push for: ${signal.type}`);
        } catch (notifError) {
          console.error(`${TAG} Failed to send push for ${signal.type}:`, notifError);
          // Continue with other signals even if one fails
        }
      }
    } else {
      console.log(`${TAG} No high-severity signals, skipping push notifications`);
    }

    console.log(`${TAG} Done — ${signals.length} signal(s), ${topMovers.length} top mover(s), ${breakingNews.length} breaking news item(s).`);

  } catch (error) {
    console.error(`${TAG} Error:`, error);
  }
});

// ============================================================================
// PUSH NOTIFICATIONS (FCM)
// ============================================================================

/**
 * Internal helper: Send push notification to a user's devices
 */
async function sendPushToUser(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
  imageUrl?: string,
  badge?: number
): Promise<{ success: boolean; sent: number; failed: number; message?: string }> {
  const TAG = "[sendPushToUser]";

  console.log(`${TAG} Sending notification to user: ${userId}`);

  try {
    // 1. Fetch user's FCM tokens
    const tokensSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("fcmTokens")
      .where("active", "==", true)
      .get();

    if (tokensSnapshot.empty) {
      console.log(`${TAG} No active FCM tokens for user: ${userId}`);
      return { success: true, sent: 0, failed: 0, message: "No active tokens" };
    }

    const tokens = tokensSnapshot.docs.map(doc => doc.data().token as string);
    console.log(`${TAG} Found ${tokens.length} active token(s)`);

    // 2. Construct FCM message
    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title,
        body,
        ...(imageUrl && { imageUrl }),
      },
      data: data || {},
      apns: {
        payload: {
          aps: {
            alert: { title, body },
            badge: badge ?? 0,
            sound: "default",
            "content-available": 1,
          },
        },
      },
    };

    // 3. Send notification
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`${TAG} Sent: ${response.successCount}/${tokens.length}`);

    // 4. Clean up invalid tokens
    if (response.failureCount > 0) {
      const tokensToDelete: string[] = [];

      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            tokensToDelete.push(tokens[idx]);
          }
        }
      });

      // Deactivate invalid tokens
      const batch = db.batch();
      tokensToDelete.forEach(token => {
        const tokenRef = db
          .collection("users")
          .doc(userId)
          .collection("fcmTokens")
          .doc(token);
        batch.update(tokenRef, { active: false });
      });

      if (tokensToDelete.length > 0) {
        await batch.commit();
        console.log(`${TAG} Deactivated ${tokensToDelete.length} invalid token(s)`);
      }
    }

    return {
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
    };

  } catch (error) {
    console.error(`${TAG} Error:`, error);
    return { success: false, sent: 0, failed: 0, message: error instanceof Error ? error.message : "Unknown error" };
  }
}

/**
 * Exported Cloud Function: Send push notification
 *
 * Callable function for sending push notifications to a specific user.
 */
export const sendPushNotification = onCall<{
  userId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
  imageUrl?: string;
  badge?: number;
}>({
  memory: "256MiB",
  timeoutSeconds: 30,
}, async (request) => {
  const { userId, title, body, data, imageUrl, badge } = request.data;
  return await sendPushToUser(userId, title, body, data, imageUrl, badge);
});

/**
 * Test push notification
 *
 * Sends a test notification to the authenticated user's devices.
 * Useful for testing FCM token registration and notification delivery.
 *
 * Usage from iOS:
 * ```swift
 * let testNotif = functions.httpsCallable("sendTestNotification")
 * try await testNotif.call()
 * ```
 */
export const sendTestNotification = onCall({
  memory: "256MiB",
  timeoutSeconds: 30,
}, async (request) => {
  const TAG = "[sendTestNotification]";

  // Get authenticated user
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = request.auth.uid;
  console.log(`${TAG} Sending test notification to user: ${userId}`);

  try {
    const result = await sendPushToUser(
      userId,
      "🔔 Test Notification",
      "CryptoSage push notifications are working! Tap to view your portfolio.",
      {
        type: "portfolioAlert",
        screen: "portfolio",
      },
      undefined,
      1
    );

    console.log(`${TAG} Test notification result:`, result);
    return result;

  } catch (error) {
    console.error(`${TAG} Error:`, error);
    throw new HttpsError("internal", "Failed to send test notification");
  }
});

/**
 * Send price alert notification
 *
 * Called when a price threshold is crossed. Sends push notification to user.
 *
 * @param userId - User who set the alert
 * @param symbol - Coin symbol (e.g., "BTC", "ETH")
 * @param currentPrice - Current price that triggered alert
 * @param targetPrice - User's target price
 * @param isAbove - True if price went above target, false if below
 * @param changePercent - Price change percentage
 */
export const sendPriceAlertNotification = onCall<{
  userId: string;
  symbol: string;
  currentPrice: number;
  targetPrice: number;
  isAbove: boolean;
  changePercent?: number;
  alertCondition?: string;
}>({
  memory: "256MiB",
  timeoutSeconds: 30,
}, async (request) => {
  const TAG = "[sendPriceAlertNotification]";
  const { userId, symbol, currentPrice, targetPrice, isAbove, changePercent, alertCondition } = request.data;

  console.log(`${TAG} Price alert for ${symbol}: $${currentPrice}`);

  try {
    // Check user preferences
    const prefsDoc = await db
      .collection("users")
      .doc(userId)
      .collection("preferences")
      .doc("notifications")
      .get();

    const prefs = prefsDoc.exists ? prefsDoc.data() : { priceAlerts: true };

    if (!prefs?.priceAlerts) {
      console.log(`${TAG} User has disabled price alerts`);
      return { success: true, sent: 0, message: "Price alerts disabled" };
    }

    // Construct notification
    const direction = isAbove ? "above" : "below";
    const emoji = isAbove ? "🚀" : "📉";
    const priceFormatted = currentPrice.toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      minimumFractionDigits: 2,
      maximumFractionDigits: currentPrice < 1 ? 6 : 2,
    });

    let title = `${emoji} ${symbol} Alert`;
    let body = `${symbol} is now ${priceFormatted}`;

    if (alertCondition) {
      body = `${symbol}: ${alertCondition} — ${priceFormatted}`;
    } else {
      body = `${symbol} ${direction} ${priceFormatted}`;
    }

    if (changePercent) {
      const sign = changePercent > 0 ? "+" : "";
      body += ` (${sign}${changePercent.toFixed(2)}%)`;
    }

    // Send notification
    const result = await sendPushToUser(
      userId,
      title,
      body,
      {
        type: "priceAlert",
        symbol,
        currentPrice: currentPrice.toString(),
        targetPrice: targetPrice.toString(),
        isAbove: isAbove.toString(),
      }
    );

    return result;

  } catch (error) {
    console.error(`${TAG} Error:`, error);
    throw new HttpsError("internal", "Failed to send price alert notification");
  }
});

/**
 * Send portfolio alert notification
 *
 * Called when portfolio value changes significantly.
 *
 * @param userId - User ID
 * @param totalValue - Current total portfolio value
 * @param changeAmount - Dollar amount change
 * @param changePercent - Percentage change
 * @param topMovers - Top performing/losing holdings
 */
export const sendPortfolioAlertNotification = onCall<{
  userId: string;
  totalValue: number;
  changeAmount: number;
  changePercent: number;
  topMovers?: Array<{ symbol: string; change: number }>;
}>({
  memory: "256MiB",
  timeoutSeconds: 30,
}, async (request) => {
  const TAG = "[sendPortfolioAlertNotification]";
  const { userId, totalValue, changeAmount, changePercent, topMovers } = request.data;

  console.log(`${TAG} Portfolio alert for user: ${userId}, change: ${changePercent}%`);

  try {
    // Check user preferences
    const prefsDoc = await db
      .collection("users")
      .doc(userId)
      .collection("preferences")
      .doc("notifications")
      .get();

    const prefs = prefsDoc.exists ? prefsDoc.data() : {
      portfolioAlerts: true,
      portfolioThreshold: 5.0,
    };

    if (!prefs?.portfolioAlerts) {
      console.log(`${TAG} User has disabled portfolio alerts`);
      return { success: true, sent: 0, message: "Portfolio alerts disabled" };
    }

    // Check if change exceeds threshold
    if (Math.abs(changePercent) < prefs.portfolioThreshold) {
      console.log(`${TAG} Change ${changePercent}% below threshold ${prefs.portfolioThreshold}%`);
      return { success: true, sent: 0, message: "Below threshold" };
    }

    // Construct notification
    const emoji = changePercent > 0 ? "📈" : "📉";
    const direction = changePercent > 0 ? "up" : "down";
    const valueFormatted = totalValue.toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      minimumFractionDigits: 2,
    });
    const changeFormatted = Math.abs(changeAmount).toLocaleString("en-US", {
      style: "currency",
      currency: "USD",
      minimumFractionDigits: 2,
    });

    const title = `${emoji} Portfolio ${direction} ${Math.abs(changePercent).toFixed(2)}%`;
    let body = `Total value: ${valueFormatted} (${changeFormatted})`;

    if (topMovers && topMovers.length > 0) {
      const mover = topMovers[0];
      body += ` • Led by ${mover.symbol} ${mover.change > 0 ? "+" : ""}${mover.change.toFixed(1)}%`;
    }

    // Send notification
    const result = await sendPushToUser(
      userId,
      title,
      body,
      {
        type: "portfolioAlert",
        totalValue: totalValue.toString(),
        changePercent: changePercent.toString(),
      }
    );

    return result;

  } catch (error) {
    console.error(`${TAG} Error:`, error);
    throw new HttpsError("internal", "Failed to send portfolio alert notification");
  }
});

/**
 * Send market alert notification to eligible users
 *
 * Called by evaluateMarketAlerts when significant market events occur.
 * Filters users based on notification preferences and severity settings.
 *
 * @param title - Alert title
 * @param body - Alert body text
 * @param severity - Alert severity (low, medium, high)
 * @param affectedSymbols - Coins affected by this alert
 * @param alertType - Type of market alert
 */
export const sendMarketAlertNotification = onCall<{
  title: string;
  body: string;
  severity: "low" | "medium" | "high";
  affectedSymbols?: string[];
  alertType?: string;
}>({
  memory: "512MiB",
  timeoutSeconds: 120,
}, async (request) => {
  const TAG = "[sendMarketAlertNotification]";
  const { title, body, severity, affectedSymbols, alertType } = request.data;

  console.log(`${TAG} Sending ${severity} market alert to eligible users`);

  try {
    // Fetch all users with notification preferences
    const usersSnapshot = await db.collection("users").get();
    let totalSent = 0;

    const sendPromises: Promise<any>[] = [];

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      // Check user preferences
      const prefsDoc = await db
        .collection("users")
        .doc(userId)
        .collection("preferences")
        .doc("notifications")
        .get();

      const prefs = prefsDoc.exists ? prefsDoc.data() : {
        marketAlerts: true,
        marketSeverity: "high",
      };

      if (!prefs?.marketAlerts) {
        continue;
      }

      // Check severity filter
      const severityOrder: Record<string, number> = { low: 1, medium: 2, high: 3 };
      const userMinSeverity = severityOrder[prefs.marketSeverity] || 3;
      const alertSeverity = severityOrder[severity];

      if (alertSeverity < userMinSeverity) {
        continue;
      }

      // Send notification to this user
      const promise = sendPushToUser(
        userId,
        title,
        body,
        {
          type: "marketAlert",
          severity,
          alertType: alertType || "general",
          ...(affectedSymbols && { symbols: affectedSymbols.join(",") }),
        }
      ).then(result => {
        if (result.sent > 0) {
          totalSent += result.sent;
        }
        return result;
      }).catch(err => {
        console.error(`${TAG} Failed to send to ${userId}:`, err);
        return { success: false, sent: 0, failed: 0 };
      });

      sendPromises.push(promise);
    }

    // Send all notifications in parallel
    await Promise.allSettled(sendPromises);

    console.log(`${TAG} Total notifications sent: ${totalSent}`);

    return {
      success: true,
      sent: totalSent,
      message: `Sent to ${totalSent} device(s)`,
    };

  } catch (error) {
    console.error(`${TAG} Error:`, error);
    throw new HttpsError("internal", "Failed to send market alert notifications");
  }
});

/**
 * Internal helper function for sending market alerts to all users
 * Called by evaluateMarketAlerts scheduled function
 *
 * @param title - Alert title
 * @param body - Alert body
 * @param severity - Alert severity
 * @param affectedSymbols - Symbols affected
 */
async function sendMarketAlertToAllUsers(
  title: string,
  body: string,
  severity: "low" | "medium" | "high",
  affectedSymbols: string[] = []
): Promise<void> {
  const TAG = "[sendMarketAlertToAllUsers]";

  try {
    // Fetch all users with notification preferences
    const usersSnapshot = await db.collection("users").get();
    let totalSent = 0;

    const sendPromises: Promise<any>[] = [];

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      // Check user preferences
      const prefsDoc = await db
        .collection("users")
        .doc(userId)
        .collection("preferences")
        .doc("notifications")
        .get();

      const prefs = prefsDoc.exists ? prefsDoc.data() : {
        marketAlerts: true,
        marketSeverity: "high",
      };

      if (!prefs?.marketAlerts) {
        continue;
      }

      // Check severity filter
      const severityOrder: Record<string, number> = { low: 1, medium: 2, high: 3 };
      const userMinSeverity = severityOrder[prefs.marketSeverity] || 3;
      const alertSeverity = severityOrder[severity];

      if (alertSeverity < userMinSeverity) {
        continue;
      }

      // Fetch user's FCM tokens
      const tokensSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("fcmTokens")
        .where("active", "==", true)
        .get();

      if (tokensSnapshot.empty) {
        continue;
      }

      const tokens = tokensSnapshot.docs.map(doc => doc.data().token as string);

      // Construct FCM message
      const message: admin.messaging.MulticastMessage = {
        tokens,
        notification: {
          title,
          body,
        },
        data: {
          type: "marketAlert",
          severity,
          symbols: affectedSymbols.join(","),
        },
        apns: {
          payload: {
            aps: {
              alert: { title, body },
              badge: 0,
              sound: "default",
              "content-available": 1,
            },
          },
        },
      };

      // Send notification
      const promise = admin.messaging()
        .sendEachForMulticast(message)
        .then(async (response) => {
          totalSent += response.successCount;

          // Clean up invalid tokens
          if (response.failureCount > 0) {
            const batch = db.batch();
            response.responses.forEach((resp, idx) => {
              if (!resp.success) {
                const errorCode = resp.error?.code;
                if (
                  errorCode === "messaging/invalid-registration-token" ||
                  errorCode === "messaging/registration-token-not-registered"
                ) {
                  const tokenRef = db
                    .collection("users")
                    .doc(userId)
                    .collection("fcmTokens")
                    .doc(tokens[idx]);
                  batch.update(tokenRef, { active: false });
                }
              }
            });
            await batch.commit();
          }
        })
        .catch(err => {
          console.error(`${TAG} Failed to send to ${userId}:`, err);
        });

      sendPromises.push(promise);
    }

    // Send all notifications in parallel
    await Promise.allSettled(sendPromises);

    console.log(`${TAG} Total notifications sent: ${totalSent}`);
  } catch (error) {
    console.error(`${TAG} Error:`, error);
  }
}

// ============================================================================
// PRIVACY & GDPR COMPLIANCE
// ============================================================================

// Re-export privacy functions
export {
  exportUserData,
  deleteUserData,
  updateConsent,
  getConsentStatus,
} from "./privacy";

// ============================================================================
// AGENT API — External AI agent integration
// ============================================================================

export {
  generateAgentApiKey,
  listAgentApiKeys,
  revokeAgentApiKey,
  agentUpdatePortfolio,
  agentRecordTrade,
  agentPushSignal,
  agentHeartbeat,
  agentGetCommands,
  agentCompleteCommand,
  agentDashboard,
} from "./agentApi";
