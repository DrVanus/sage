/**
 * CryptoSage AI - Agent API
 *
 * HTTP endpoints for external AI agents (OpenClaw, custom bots) to push data
 * and receive commands. Agents authenticate via API keys generated in the app.
 *
 * Endpoints:
 * - generateAgentApiKey (onCall) - User generates a key in-app
 * - listAgentApiKeys (onCall) - List user's keys
 * - revokeAgentApiKey (onCall) - Deactivate a key
 * - agentUpdatePortfolio (onRequest) - Agent pushes portfolio state
 * - agentRecordTrade (onRequest) - Agent records a trade
 * - agentPushSignal (onRequest) - Agent pushes analysis/signal
 * - agentHeartbeat (onRequest) - Agent status ping
 * - agentGetCommands (onRequest) - Agent polls for pending commands
 * - agentCompleteCommand (onRequest) - Agent marks command done
 */

import * as admin from "firebase-admin";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import * as crypto from "crypto";
import { sendPushNotificationToUser } from "./pushNotifications";

function getDb(): admin.firestore.Firestore {
  return admin.firestore();
}

// ============================================================================
// TYPES
// ============================================================================

interface AgentKeyDoc {
  userId: string;
  keyPrefix: string;
  name: string;
  permissions: string[];
  isActive: boolean;
  rateLimit: { requestsPerMinute: number; requestsPerHour: number };
  createdAt: admin.firestore.Timestamp;
  lastUsedAt: admin.firestore.Timestamp | null;
  requestCountMinute: number;
  requestCountHour: number;
  minuteWindowStart: number;
  hourWindowStart: number;
}

interface AuthenticatedAgent {
  userId: string;
  keyHash: string;
  name: string;
  permissions: string[];
}

// ============================================================================
// AGENT AUTHENTICATION
// ============================================================================

function hashApiKey(key: string): string {
  return crypto.createHash("sha256").update(key).digest("hex");
}

function generateSecureKey(): string {
  const bytes = crypto.randomBytes(36);
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "sage_";
  for (const b of bytes) {
    result += chars[b % chars.length];
  }
  return result;
}

async function authenticateAgent(
  req: { headers: { authorization?: string }; method: string },
): Promise<AuthenticatedAgent> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    throw new HttpsError("unauthenticated", "Missing or invalid Authorization header");
  }

  const rawKey = authHeader.slice(7);
  if (!rawKey.startsWith("sage_") || rawKey.length < 20) {
    throw new HttpsError("unauthenticated", "Invalid API key format");
  }

  const keyHash = hashApiKey(rawKey);
  const db = getDb();
  const keyDoc = await db.collection("agentApiKeys").doc(keyHash).get();

  if (!keyDoc.exists) {
    throw new HttpsError("unauthenticated", "Invalid API key");
  }

  const data = keyDoc.data() as AgentKeyDoc;
  if (!data.isActive) {
    throw new HttpsError("permission-denied", "API key has been revoked");
  }

  // Rate limiting
  const now = Date.now();
  const minuteWindow = 60 * 1000;
  const hourWindow = 60 * 60 * 1000;
  const updates: Record<string, unknown> = {
    lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Reset counters if window expired
  if (now - (data.minuteWindowStart || 0) > minuteWindow) {
    updates.requestCountMinute = 1;
    updates.minuteWindowStart = now;
  } else if ((data.requestCountMinute || 0) >= data.rateLimit.requestsPerMinute) {
    throw new HttpsError("resource-exhausted", "Rate limit exceeded (per minute)");
  } else {
    updates.requestCountMinute = admin.firestore.FieldValue.increment(1);
  }

  if (now - (data.hourWindowStart || 0) > hourWindow) {
    updates.requestCountHour = 1;
    updates.hourWindowStart = now;
  } else if ((data.requestCountHour || 0) >= data.rateLimit.requestsPerHour) {
    throw new HttpsError("resource-exhausted", "Rate limit exceeded (per hour)");
  } else {
    updates.requestCountHour = admin.firestore.FieldValue.increment(1);
  }

  // Non-blocking update
  keyDoc.ref.update(updates).catch(() => {});

  return {
    userId: data.userId,
    keyHash,
    name: data.name,
    permissions: data.permissions,
  };
}

function requirePermission(agent: AuthenticatedAgent, permission: string): void {
  if (!agent.permissions.includes(permission)) {
    throw new HttpsError("permission-denied", `Missing permission: ${permission}`);
  }
}

// ============================================================================
// API KEY MANAGEMENT (onCall — called from iOS app)
// ============================================================================

export const generateAgentApiKey = onCall({
  timeoutSeconds: 10,
  memory: "256MiB",

}, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { name = "My Agent" } = request.data || {};
  const cleanName = typeof name === "string" ? name.slice(0, 50).trim() : "My Agent";

  // Limit: max 5 keys per user
  const db = getDb();
  const existing = await db.collection("agentApiKeys")
    .where("userId", "==", userId)
    .where("isActive", "==", true)
    .get();

  if (existing.size >= 5) {
    throw new HttpsError("resource-exhausted", "Maximum 5 active API keys per account");
  }

  const rawKey = generateSecureKey();
  const keyHash = hashApiKey(rawKey);

  await db.collection("agentApiKeys").doc(keyHash).set({
    userId,
    keyPrefix: rawKey.slice(0, 12),
    name: cleanName,
    permissions: [
      "read_portfolio",
      "write_portfolio",
      "write_signals",
      "write_trades",
      "read_commands",
      "write_status",
    ],
    isActive: true,
    rateLimit: { requestsPerMinute: 60, requestsPerHour: 500 },
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    lastUsedAt: null,
    requestCountMinute: 0,
    requestCountHour: 0,
    minuteWindowStart: 0,
    hourWindowStart: 0,
  } as Omit<AgentKeyDoc, "createdAt" | "lastUsedAt"> & Record<string, unknown>);

  return {
    apiKey: rawKey,
    keyPrefix: rawKey.slice(0, 12),
    name: cleanName,
  };
});

export const listAgentApiKeys = onCall({
  timeoutSeconds: 10,
  memory: "256MiB",

}, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const db = getDb();
  const snapshot = await db.collection("agentApiKeys")
    .where("userId", "==", userId)
    .orderBy("createdAt", "desc")
    .get();

  return {
    keys: snapshot.docs.map(doc => {
      const data = doc.data();
      return {
        id: doc.id,
        keyPrefix: data.keyPrefix,
        name: data.name,
        isActive: data.isActive,
        permissions: data.permissions,
        createdAt: data.createdAt?.toDate?.()?.toISOString() || null,
        lastUsedAt: data.lastUsedAt?.toDate?.()?.toISOString() || null,
      };
    }),
  };
});

export const revokeAgentApiKey = onCall({
  timeoutSeconds: 10,
  memory: "256MiB",

}, async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { keyId } = request.data || {};
  if (typeof keyId !== "string") {
    throw new HttpsError("invalid-argument", "keyId is required");
  }

  const db = getDb();
  const keyDoc = await db.collection("agentApiKeys").doc(keyId).get();

  if (!keyDoc.exists) {
    throw new HttpsError("not-found", "API key not found");
  }

  const data = keyDoc.data()!;
  if (data.userId !== userId) {
    throw new HttpsError("permission-denied", "Not your API key");
  }

  await keyDoc.ref.update({ isActive: false });

  return { success: true };
});

// ============================================================================
// AGENT DATA ENDPOINTS (onRequest — called from external agents)
// ============================================================================

export const agentUpdatePortfolio = onRequest({
  timeoutSeconds: 15,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "write_portfolio");

    const { agentId = "sage-trader", balance_usd, positions, total_value_usd, strategy } = req.body;

    if (typeof balance_usd !== "number" || typeof positions !== "object") {
      res.status(400).json({ error: "balance_usd (number) and positions (object) required" });
      return;
    }

    const db = getDb();
    await db.collection("users").doc(agent.userId)
      .collection("agentPortfolio").doc(String(agentId)).set({
        balance_usd,
        positions: positions || {},
        total_value_usd: typeof total_value_usd === "number" ? total_value_usd : balance_usd,
        strategy: typeof strategy === "string" ? strategy.slice(0, 50) : "unknown",
        agent_name: agent.name,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.json({ success: true });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});

export const agentRecordTrade = onRequest({
  timeoutSeconds: 15,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "write_trades");

    const {
      action, symbol, quantity, price, usd_amount,
      reason, composite_score, fear_greed, confidence, paper,
      analysis,
    } = req.body;

    if (!action || !symbol || typeof price !== "number") {
      res.status(400).json({ error: "action, symbol, and price are required" });
      return;
    }

    const db = getDb();
    const tradeData = {
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      action: String(action).toUpperCase().slice(0, 10),
      symbol: String(symbol).toUpperCase().slice(0, 10),
      quantity: typeof quantity === "number" ? quantity : 0,
      price,
      usd_amount: typeof usd_amount === "number" ? usd_amount : 0,
      reason: typeof reason === "string" ? reason.slice(0, 500) : "",
      composite_score: typeof composite_score === "number" ? composite_score : null,
      fear_greed: typeof fear_greed === "number" ? fear_greed : null,
      confidence: typeof confidence === "string" ? confidence.slice(0, 20) : null,
      paper: paper !== false,
      agent_name: agent.name,
      analysis: typeof analysis === "object" && analysis !== null ? analysis : null,
    };

    await db.collection("users").doc(agent.userId)
      .collection("agentTrades").add(tradeData);

    // Send push notification for trade execution
    try {
      await sendPushNotificationToUser(agent.userId, {
        title: `${tradeData.action} ${tradeData.symbol}`,
        body: `${agent.name}: ${tradeData.action} ${tradeData.quantity} ${tradeData.symbol} @ $${price.toLocaleString()}`,
        data: {
          type: "agent_trade",
          symbol: tradeData.symbol,
          action: tradeData.action,
        },
      });
    } catch {
      // Non-critical — don't fail the trade record
    }

    res.json({ success: true });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});

export const agentPushSignal = onRequest({
  timeoutSeconds: 15,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "write_signals");

    const {
      symbol, signal, composite_score, fear_greed_index,
      fear_greed_category, rsi, macd_trend, primary_trend,
      confidence, risk_score, reasoning, indicators, structure,
    } = req.body;

    if (!symbol || !signal || typeof composite_score !== "number") {
      res.status(400).json({ error: "symbol, signal, and composite_score are required" });
      return;
    }

    const db = getDb();
    // TTL: auto-delete after 24h
    const ttl = new Date();
    ttl.setHours(ttl.getHours() + 24);

    await db.collection("users").doc(agent.userId)
      .collection("agentSignals").add({
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        symbol: String(symbol).toUpperCase().slice(0, 10),
        signal: String(signal).toLowerCase().slice(0, 20),
        composite_score,
        fear_greed_index: typeof fear_greed_index === "number" ? fear_greed_index : null,
        fear_greed_category: typeof fear_greed_category === "string" ? fear_greed_category.slice(0, 30) : null,
        rsi: typeof rsi === "number" ? rsi : null,
        macd_trend: typeof macd_trend === "string" ? macd_trend.slice(0, 20) : null,
        primary_trend: typeof primary_trend === "string" ? primary_trend.slice(0, 20) : null,
        confidence: typeof confidence === "string" ? confidence.slice(0, 20) : null,
        risk_score: typeof risk_score === "number" ? risk_score : null,
        reasoning: typeof reasoning === "string" ? reasoning.slice(0, 1000) : null,
        indicators: typeof indicators === "object" && indicators !== null ? indicators : null,
        structure: typeof structure === "object" && structure !== null ? structure : null,
        agent_name: agent.name,
        ttl: admin.firestore.Timestamp.fromDate(ttl),
      });

    res.json({ success: true });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});

export const agentHeartbeat = onRequest({
  timeoutSeconds: 10,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "write_status");

    const { agentId = "sage-trader", status, daily_pnl, open_positions, note, circuit_breaker_active } = req.body;

    const db = getDb();
    await db.collection("users").doc(agent.userId)
      .collection("agentStatus").doc(String(agentId)).set({
        last_heartbeat: admin.firestore.FieldValue.serverTimestamp(),
        status: typeof status === "string" ? status.slice(0, 20) : "active",
        daily_pnl: typeof daily_pnl === "number" ? daily_pnl : null,
        open_positions: typeof open_positions === "number" ? open_positions : null,
        note: typeof note === "string" ? note.slice(0, 200) : null,
        circuit_breaker_active: circuit_breaker_active === true,
        agent_name: agent.name,
        session_count: admin.firestore.FieldValue.increment(1),
      }, { merge: true });

    res.json({ success: true });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});

// ============================================================================
// COMMAND QUEUE (Agent polls for commands from app)
// ============================================================================

export const agentGetCommands = onRequest({
  timeoutSeconds: 10,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "read_commands");

    const db = getDb();
    const snapshot = await db.collection("users").doc(agent.userId)
      .collection("agentCommands")
      .where("status", "==", "pending")
      .orderBy("created_at", "asc")
      .limit(10)
      .get();

    const commands = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data(),
      created_at: doc.data().created_at?.toDate?.()?.toISOString() || null,
    }));

    // Mark as acknowledged
    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: "acknowledged",
        acknowledged_at: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    if (!snapshot.empty) {
      await batch.commit();
    }

    res.json({ commands });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});

export const agentCompleteCommand = onRequest({
  timeoutSeconds: 10,
  memory: "256MiB",
  cors: true,

}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const agent = await authenticateAgent(req);
    requirePermission(agent, "read_commands");

    const { commandId, result, status = "completed" } = req.body;
    if (typeof commandId !== "string") {
      res.status(400).json({ error: "commandId is required" });
      return;
    }

    const db = getDb();
    const cmdRef = db.collection("users").doc(agent.userId)
      .collection("agentCommands").doc(commandId);

    const cmdDoc = await cmdRef.get();
    if (!cmdDoc.exists) {
      res.status(404).json({ error: "Command not found" });
      return;
    }

    await cmdRef.update({
      status: status === "failed" ? "failed" : "completed",
      result: typeof result === "string" ? result.slice(0, 1000) : null,
      completed_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ success: true });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    res.status(e.code === "unauthenticated" || e.code === "permission-denied" ? 403 : 500)
      .json({ error: e.message || "Internal error" });
  }
});
