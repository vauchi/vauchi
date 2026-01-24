# P07: Relay Persistence and Redundancy

**Priority**: MEDIUM (post-MVP)
**Status**: Research/Architecture
**Effort**: 2-3 weeks

## Problem

Current relay is memory-only:
- Blobs lost on restart
- No message redundancy if relay fails
- Single point of failure
- No delivery guarantees

## Requirements

### Must Have
- Messages survive relay restart
- Delivery receipt/acknowledgment
- Message expiration (TTL)
- Bounded storage growth

### Should Have
- Multiple relay support
- Automatic failover
- Geographic distribution
- Offline message queue

### Nice to Have
- Relay federation
- Load balancing
- Self-hosted relay support

---

## Architecture Options

### Option A: SQLite Persistence (Simple)

**Current relay + SQLite for blob storage.**

```
┌─────────────────┐
│  vauchi-relay   │
├─────────────────┤
│  In-memory WS   │
│  connections    │
├─────────────────┤
│  SQLite         │
│  - blobs        │
│  - delivery     │
│  - expiry       │
└─────────────────┘
```

**Pros:**
- Minimal code changes
- Single deployment
- No external dependencies
- Works offline

**Cons:**
- Single point of failure
- No horizontal scaling
- Disk I/O bottleneck

**Implementation:**
```rust
// relay/src/persistence.rs
pub struct PersistentBlobStore {
    db: rusqlite::Connection,
}

impl PersistentBlobStore {
    pub fn store(&self, recipient_id: &str, blob: &[u8], ttl: Duration) -> Result<BlobId>;
    pub fn retrieve(&self, recipient_id: &str) -> Result<Vec<Blob>>;
    pub fn acknowledge(&self, blob_id: BlobId) -> Result<()>;
    pub fn cleanup_expired(&self) -> Result<usize>;
}
```

**Schema:**
```sql
CREATE TABLE blobs (
    id TEXT PRIMARY KEY,
    recipient_id TEXT NOT NULL,
    sender_id TEXT,
    ciphertext BLOB NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    acknowledged INTEGER DEFAULT 0
);

CREATE INDEX idx_recipient ON blobs(recipient_id, acknowledged);
CREATE INDEX idx_expires ON blobs(expires_at);
```

---

### Option B: Multi-Relay with Shared Storage (Scalable)

**Multiple relay instances sharing PostgreSQL/Redis.**

```
              ┌─────────────┐
              │   Client    │
              └──────┬──────┘
                     │
         ┌──────────┼──────────┐
         ▼          ▼          ▼
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ Relay 1 │ │ Relay 2 │ │ Relay 3 │
    └────┬────┘ └────┬────┘ └────┬────┘
         │          │          │
         └──────────┼──────────┘
                    ▼
              ┌───────────┐
              │ PostgreSQL│
              │  + Redis  │
              └───────────┘
```

**Pros:**
- Horizontal scaling
- High availability
- Geographic distribution
- Load balancing

**Cons:**
- Operational complexity
- External dependencies
- More expensive
- Latency considerations

**Implementation:**
```rust
// relay/src/multi_relay.rs
pub struct RelayCluster {
    relays: Vec<RelayConfig>,
    db: PostgresPool,
    cache: RedisPool,
}

impl RelayCluster {
    pub async fn store(&self, msg: Message) -> Result<()> {
        // Store in Postgres
        self.db.store_message(&msg).await?;
        // Notify via Redis pub/sub
        self.cache.publish(&msg.recipient_id, &msg.id).await?;
        Ok(())
    }
}
```

---

### Option C: Client-Side Redundancy (Decentralized)

**Clients connect to multiple relays, dedup on receive.**

```
    ┌─────────┐              ┌─────────┐
    │ Alice   │              │   Bob   │
    └────┬────┘              └────┬────┘
         │                        │
    ┌────┴────┬────────┬────┴────┐
    ▼         ▼        ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│Relay 1│ │Relay 2│ │Relay 3│ │Relay 4│
└───────┘ └───────┘ └───────┘ └───────┘
     (independent, no shared state)
```

**Pros:**
- No single point of failure
- Privacy preserving
- Simple relay implementation
- Self-hostable

**Cons:**
- More client complexity
- Higher bandwidth (duplicate sends)
- Eventual consistency challenges
- Message deduplication required

**Implementation:**
```rust
// core/src/network/multi_relay.rs
pub struct MultiRelayClient {
    relays: Vec<RelayConnection>,
    message_ids: HashSet<MessageId>,
}

impl MultiRelayClient {
    pub async fn send(&self, msg: Message) -> Result<()> {
        // Send to all relays
        let results = futures::future::join_all(
            self.relays.iter().map(|r| r.send(&msg))
        ).await;
        // Success if any relay accepted
        if results.iter().any(|r| r.is_ok()) {
            Ok(())
        } else {
            Err(Error::AllRelaysFailed)
        }
    }

    pub fn receive(&mut self, msg: Message) -> Option<Message> {
        // Dedup by message ID
        if self.message_ids.insert(msg.id) {
            Some(msg)
        } else {
            None // Already seen
        }
    }
}
```

---

## Recommendation

### Phase 1: SQLite Persistence (MVP+)

1. Add SQLite to existing relay
2. Persist blobs with TTL (7 days default)
3. Add acknowledgment protocol
4. Run cleanup job hourly
5. **Effort: 3-5 days**

### Phase 2: Multi-Relay Client (Post-MVP)

1. Add relay list to client config
2. Implement parallel send
3. Add message deduplication
4. Handle partial delivery
5. **Effort: 1 week**

### Phase 3: Relay Federation (Future)

1. Design federation protocol
2. Implement relay discovery
3. Add geographic routing
4. Build monitoring/ops tools
5. **Effort: 2-3 weeks**

---

## Message Delivery Protocol

### Current (Unreliable)
```
Client A                    Relay                    Client B
    │                         │                         │
    │──── send(blob) ─────────>│                         │
    │<─── ack ────────────────│                         │
    │                         │──── push(blob) ────────>│
    │                         │<─── (connection lost)   │
    │                         │                         │
    │      (blob lost if B offline)                     │
```

### Proposed (Reliable)
```
Client A                    Relay                    Client B
    │                         │                         │
    │──── send(blob, id) ─────>│                         │
    │<─── stored(id) ─────────│                         │
    │                         │  (persisted to disk)    │
    │                         │                         │
    │                         │──── push(blob, id) ────>│
    │                         │<─── ack(id) ────────────│
    │                         │  (marked delivered)     │
    │                         │                         │
    │ (B reconnects later)    │                         │
    │                         │<─── poll ───────────────│
    │                         │──── pending: [blob] ───>│
    │                         │<─── ack(id) ────────────│
```

### Message Format
```rust
#[derive(Serialize, Deserialize)]
pub struct RelayMessage {
    pub id: [u8; 16],           // UUID for dedup
    pub recipient_id: String,   // Public key hex
    pub sender_id: Option<String>,
    pub ciphertext: Vec<u8>,
    pub timestamp: u64,
    pub ttl_hours: u32,
}

#[derive(Serialize, Deserialize)]
pub enum RelayResponse {
    Stored { id: [u8; 16] },
    Delivered { id: [u8; 16] },
    NotFound,
    RateLimited { retry_after: u32 },
}
```

---

## Storage Limits

### Per-User Quotas
```rust
pub struct StorageQuota {
    /// Max pending blobs per recipient
    pub max_pending: usize,         // Default: 100
    /// Max blob size in bytes
    pub max_blob_size: usize,       // Default: 64KB
    /// Max total storage per recipient
    pub max_total_bytes: usize,     // Default: 1MB
    /// Default TTL for blobs
    pub default_ttl: Duration,      // Default: 7 days
    /// Max TTL allowed
    pub max_ttl: Duration,          // Default: 30 days
}
```

### Cleanup Policy
```rust
// Run hourly
pub fn cleanup_expired(db: &Connection, quota: &StorageQuota) -> Result<CleanupStats> {
    // 1. Delete expired blobs
    let expired = db.execute(
        "DELETE FROM blobs WHERE expires_at < ?",
        [now()]
    )?;

    // 2. Delete oldest if over quota
    let over_quota = db.execute(r#"
        DELETE FROM blobs WHERE id IN (
            SELECT id FROM blobs b
            WHERE (SELECT COUNT(*) FROM blobs WHERE recipient_id = b.recipient_id) > ?
            ORDER BY created_at ASC
            LIMIT 10
        )
    "#, [quota.max_pending])?;

    // 3. Vacuum if significant deletions
    if expired + over_quota > 1000 {
        db.execute("VACUUM", [])?;
    }

    Ok(CleanupStats { expired, over_quota })
}
```

---

## Security Considerations

### Relay Trust Model
- Relay CANNOT read message content (E2E encrypted)
- Relay CAN see metadata: sender/recipient IDs, timing, size
- Relay CAN drop messages (availability attack)
- Relay CANNOT forge messages (signature verification)

### Mitigations
1. **Multi-relay**: Redundancy prevents single-relay censorship
2. **Sender anonymity**: Optional sender ID (anonymous tips)
3. **Timing obfuscation**: Random delays in delivery (future)
4. **Onion routing**: Route through multiple relays (future, see Tor mode)

### Persistence Security
```rust
// Blobs are already encrypted by sender
// Additional at-rest encryption is optional but recommended
pub struct EncryptedBlobStore {
    inner: BlobStore,
    key: SymmetricKey,  // Derived from relay's secret
}

impl EncryptedBlobStore {
    pub fn store(&self, blob: &[u8]) -> Result<BlobId> {
        let encrypted = self.key.encrypt(blob)?;
        self.inner.store(&encrypted)
    }
}
```

---

## Monitoring

### Metrics to Track
```rust
// Prometheus metrics
pub struct RelayMetrics {
    blobs_stored: Counter,
    blobs_delivered: Counter,
    blobs_expired: Counter,
    storage_bytes: Gauge,
    active_connections: Gauge,
    delivery_latency: Histogram,
}
```

### Health Checks
```rust
// GET /health
pub async fn health_check(db: &Connection) -> HealthStatus {
    HealthStatus {
        database: db.is_healthy(),
        storage_usage: db.storage_usage(),
        pending_messages: db.pending_count(),
        uptime: process_uptime(),
    }
}
```

---

## Implementation Plan

### Week 1: SQLite Backend
- [ ] Add `persistence` module to relay
- [ ] Implement blob storage with TTL
- [ ] Add acknowledgment protocol
- [ ] Write migration script
- [ ] Unit tests

### Week 2: Protocol Changes
- [ ] Update relay protocol with message IDs
- [ ] Add `poll` command for pending messages
- [ ] Update clients to use new protocol
- [ ] Backward compatibility layer
- [ ] Integration tests

### Week 3: Multi-Relay (Optional)
- [ ] Add relay list configuration
- [ ] Implement parallel send in core
- [ ] Add message deduplication
- [ ] Test failover scenarios
- [ ] Documentation

---

## Open Questions

1. **Default TTL**: 7 days? 30 days? Configurable per-message?
2. **Quota enforcement**: Reject new messages or delete oldest?
3. **Sender notification**: Should sender know if recipient hasn't retrieved?
4. **Multi-relay protocol**: Standard or proprietary?
5. **Self-hosted relays**: How to discover and trust?

---

## References

- Matrix Synapse persistence model
- Signal's sealed sender
- Briar's store-and-forward
- Pond's mixing network (academic)
