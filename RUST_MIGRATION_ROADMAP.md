# Practical Migration Roadmap: Java to Rust

This document provides a step-by-step roadmap for migrating the Aion Germany emulator from Java to Rust.

## Prerequisites

### Team Requirements
- [ ] At least 2-3 developers committed to the project
- [ ] 2-3 months of Rust learning time allocated
- [ ] Management buy-in for 1.5-2.5 year timeline
- [ ] Acceptance that Java version will run in parallel during migration

### Learning Path (2-3 months)
1. **Week 1-2**: [The Rust Book](https://doc.rust-lang.org/book/)
2. **Week 3-4**: [Rust by Example](https://doc.rust-lang.org/rust-by-example/)
3. **Week 5-6**: [Async Programming in Rust](https://rust-lang.github.io/async-book/)
4. **Week 7-8**: [Tokio Tutorial](https://tokio.rs/tokio/tutorial)
5. **Week 9-10**: Small projects and exercises
6. **Week 11-12**: Proof of concept (chat server port)

### Development Environment Setup

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install useful tools
cargo install cargo-watch     # Auto-rebuild on file changes
cargo install cargo-edit      # cargo add/rm/upgrade commands
cargo install cargo-audit     # Security vulnerability scanning
cargo install flamegraph      # Performance profiling
cargo install sqlx-cli        # Database migrations

# Install IDE/Editor plugins
# VSCode: rust-analyzer
# IntelliJ: Rust plugin
```

## Phase 1: Foundation (Months 1-3)

### Month 1: Project Setup and Infrastructure

#### Week 1-2: Workspace Structure
```bash
# Create workspace
cargo new aion-rust --lib
cd aion-rust

# Create crates
cargo new --lib crates/commons
cargo new --lib crates/packets
cargo new --lib crates/database
cargo new --bin crates/login-server
cargo new --bin crates/chat-server
cargo new --bin crates/game-server

# Directory structure
mkdir -p {data,config,sql,docs,scripts}
```

**Workspace Cargo.toml:**
```toml
[workspace]
members = [
    "crates/commons",
    "crates/packets",
    "crates/database",
    "crates/login-server",
    "crates/chat-server",
    "crates/game-server",
]

[workspace.dependencies]
tokio = { version = "1.35", features = ["full"] }
sqlx = { version = "0.7", features = ["runtime-tokio-rustls", "mysql"] }
serde = { version = "1.0", features = ["derive"] }
tracing = "0.1"
tracing-subscriber = "0.3"
bytes = "1.5"
```

#### Week 3: CI/CD Setup
Create `.github/workflows/rust.yml`:
```yaml
name: Rust CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - run: cargo test --all-features
      
  clippy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          components: clippy
      - run: cargo clippy -- -D warnings
      
  fmt:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
          components: rustfmt
      - run: cargo fmt -- --check
```

#### Week 4: Commons Foundation
**Priority Tasks:**
- [ ] Basic networking types (Address, Connection trait)
- [ ] Configuration system (using `config` crate)
- [ ] Logging setup (using `tracing`)
- [ ] Error types (using `thiserror`)
- [ ] Basic utilities (time, math helpers)

**Example commons/src/lib.rs:**
```rust
pub mod config;
pub mod error;
pub mod network;
pub mod utils;

pub use error::{Error, Result};
```

### Month 2: Networking and Packets

#### Week 1-2: Networking Layer
**File: crates/commons/src/network/mod.rs**
```rust
use tokio::net::TcpStream;
use bytes::BytesMut;

pub trait Connection: Send + Sync {
    async fn send_packet(&mut self, packet: &[u8]) -> Result<()>;
    async fn receive_packet(&mut self) -> Result<Option<BytesMut>>;
    fn close(&mut self);
}

pub struct GameConnection {
    stream: TcpStream,
    read_buffer: BytesMut,
    write_buffer: BytesMut,
}

impl GameConnection {
    pub fn new(stream: TcpStream) -> Self {
        Self {
            stream,
            read_buffer: BytesMut::with_capacity(8192),
            write_buffer: BytesMut::with_capacity(8192),
        }
    }
}
```

#### Week 3-4: Packet System
**File: crates/packets/src/lib.rs**
```rust
use bytes::{Buf, BufMut, BytesMut};

pub trait Packet {
    fn opcode(&self) -> u16;
    fn encode(&self, buf: &mut BytesMut) -> Result<()>;
}

pub trait PacketDecoder {
    fn decode(opcode: u16, buf: &mut BytesMut) -> Result<Box<dyn Packet>>;
}

// Macro for packet definition
#[macro_export]
macro_rules! define_packet {
    ($name:ident, $opcode:expr, { $($field:ident: $type:ty),* }) => {
        pub struct $name {
            $(pub $field: $type),*
        }
        
        impl Packet for $name {
            fn opcode(&self) -> u16 {
                $opcode
            }
            
            fn encode(&self, buf: &mut BytesMut) -> Result<()> {
                buf.put_u16(self.opcode());
                $(
                    // Encoding logic per type
                )*
                Ok(())
            }
        }
    };
}
```

### Month 3: Database Layer

#### Week 1-2: Database Setup
```bash
# Install sqlx-cli
cargo install sqlx-cli --features mysql

# Initialize migrations
cd crates/database
sqlx database create
sqlx migrate add initial_schema
```

**File: crates/database/migrations/001_initial_schema.sql**
```sql
CREATE TABLE players (
    id INT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    account_id INT UNSIGNED NOT NULL,
    name VARCHAR(50) NOT NULL UNIQUE,
    level INT NOT NULL DEFAULT 1,
    exp BIGINT NOT NULL DEFAULT 0,
    x FLOAT NOT NULL DEFAULT 0.0,
    y FLOAT NOT NULL DEFAULT 0.0,
    z FLOAT NOT NULL DEFAULT 0.0,
    online BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_online TIMESTAMP NULL,
    INDEX idx_account (account_id),
    INDEX idx_online (online)
);
```

#### Week 3-4: Database Models
**File: crates/database/src/models/player.rs**
```rust
use sqlx::FromRow;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, FromRow)]
pub struct Player {
    pub id: u32,
    pub account_id: u32,
    pub name: String,
    pub level: i32,
    pub exp: i64,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub online: bool,
    pub created_at: DateTime<Utc>,
    pub last_online: Option<DateTime<Utc>>,
}

impl Player {
    pub async fn find_by_id(
        pool: &sqlx::MySqlPool,
        id: u32
    ) -> Result<Option<Self>> {
        sqlx::query_as!(
            Self,
            "SELECT * FROM players WHERE id = ?",
            id
        )
        .fetch_optional(pool)
        .await
        .map_err(Into::into)
    }
    
    pub async fn save(&self, pool: &sqlx::MySqlPool) -> Result<()> {
        sqlx::query!(
            "UPDATE players SET level = ?, exp = ?, x = ?, y = ?, z = ?, online = ? WHERE id = ?",
            self.level, self.exp, self.x, self.y, self.z, self.online, self.id
        )
        .execute(pool)
        .await?;
        Ok(())
    }
}
```

## Phase 2: Core Servers (Months 4-9)

### Month 4-5: Chat Server (Proof of Concept)

This is the critical proof-of-concept phase. Success here validates the entire approach.

**Goals:**
- [ ] Complete functional chat server
- [ ] Performance benchmarking vs Java version
- [ ] Team gains confidence with Rust
- [ ] Identify tooling gaps

**File: crates/chat-server/src/main.rs**
```rust
use tokio::net::TcpListener;
use tracing::{info, error};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();
    
    // Load configuration
    let config = ChatServerConfig::load("config/chat.toml")?;
    
    // Initialize database pool
    let db_pool = init_database_pool(&config.database).await?;
    
    // Start server
    let listener = TcpListener::bind(
        format!("{}:{}", config.network.bind_address, config.network.port)
    ).await?;
    
    info!("Chat server listening on {}:{}", 
        config.network.bind_address, 
        config.network.port
    );
    
    // Accept connections
    loop {
        match listener.accept().await {
            Ok((socket, addr)) => {
                info!("New connection from: {}", addr);
                let db = db_pool.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_chat_client(socket, db).await {
                        error!("Error handling client: {}", e);
                    }
                });
            }
            Err(e) => error!("Failed to accept connection: {}", e),
        }
    }
}
```

**Deliverables:**
- [ ] Functional chat server handling connections
- [ ] Message broadcasting working
- [ ] Database integration working
- [ ] Performance metrics documented
- [ ] Lessons learned documented

### Month 6-7: Login Server

**File: crates/login-server/src/main.rs**
```rust
#[tokio::main]
async fn main() -> Result<()> {
    // Similar structure to chat server
    // Focus on authentication and session management
}
```

**Tasks:**
- [ ] Account authentication
- [ ] Session management
- [ ] Token generation
- [ ] Server list management
- [ ] Ban system

### Month 8-9: Game Server Foundation

**File: crates/game-server/src/main.rs**
```rust
pub struct GameServer {
    world: Arc<RwLock<GameWorld>>,
    packet_handler: PacketHandler,
    event_bus: EventBus,
}

impl GameServer {
    pub async fn start(&mut self) -> Result<()> {
        // Initialize world
        self.world.write().await.initialize().await?;
        
        // Start packet processing
        // Start event loop
        // Accept connections
        
        Ok(())
    }
}
```

**Tasks:**
- [ ] Basic player connection handling
- [ ] World initialization
- [ ] Player spawning
- [ ] Basic movement
- [ ] Chat integration

## Phase 3: Game Logic (Months 10-21)

### Months 10-12: Core Mechanics
- [ ] Entity system
- [ ] Movement and collision
- [ ] Basic combat
- [ ] Item system
- [ ] Inventory management

### Months 13-15: Content Systems
- [ ] Quest system
- [ ] NPC system
- [ ] Spawn system
- [ ] Drop system
- [ ] Shop system

### Months 16-18: Social Features
- [ ] Guild system
- [ ] Group system
- [ ] Friend system
- [ ] Mail system
- [ ] Trade system

### Months 19-21: Advanced Features
- [ ] Instance system
- [ ] AI system
- [ ] Skill system
- [ ] Buff/debuff system
- [ ] Pet system

## Phase 4: Polish & Production (Months 22-24)

### Month 22: Performance Optimization
- [ ] Profile with flamegraph
- [ ] Optimize hot paths
- [ ] Memory optimization
- [ ] Connection pooling tuning
- [ ] Database query optimization

### Month 23: Testing & QA
- [ ] Load testing (compare with Java)
- [ ] Integration tests
- [ ] Bug fixing
- [ ] Security audit
- [ ] Documentation completion

### Month 24: Deployment
- [ ] Production deployment scripts
- [ ] Monitoring setup (Prometheus + Grafana)
- [ ] Backup systems
- [ ] Rollback procedures
- [ ] Training for operations team

## Success Metrics

### Performance Targets
- [ ] 50% reduction in memory usage
- [ ] 30% reduction in CPU usage
- [ ] 40% improvement in average latency
- [ ] 60% improvement in P99 latency
- [ ] Support 50% more concurrent players

### Quality Targets
- [ ] 90%+ code coverage
- [ ] Zero critical security vulnerabilities
- [ ] < 1% crash rate
- [ ] 99.9% uptime

## Risk Mitigation

### Technical Risks
1. **Risk**: Rust learning curve too steep
   **Mitigation**: Allocate 3 months for learning, start with simple components

2. **Risk**: Missing Java library equivalents
   **Mitigation**: Research alternatives during planning, be prepared to write custom solutions

3. **Risk**: Performance doesn't meet expectations
   **Mitigation**: Start with proof-of-concept, benchmark early and often

### Business Risks
1. **Risk**: Timeline overruns
   **Mitigation**: Incremental delivery, maintain Java version in parallel

2. **Risk**: Team burnout
   **Mitigation**: Realistic timelines, celebrate milestones, rotate challenging tasks

3. **Risk**: User disruption
   **Mitigation**: Thorough testing, gradual rollout, easy rollback plan

## Go/No-Go Decision Points

### After Month 3 (Foundation Complete)
**Evaluate:**
- Is the team comfortable with Rust?
- Are the tools adequate?
- Is the foundation solid?

**Decision**: Continue or abort?

### After Month 5 (Chat Server Complete)
**Evaluate:**
- Does Rust version meet/exceed Java performance?
- Are development patterns working?
- Is the team productive?

**Decision**: Continue to full migration or keep hybrid approach?

### After Month 9 (Core Servers Complete)
**Evaluate:**
- Are all servers working reliably?
- Is integration smooth?
- Are timelines on track?

**Decision**: Continue to game logic or stabilize?

## Conclusion

This roadmap provides a structured approach to migrating Aion Germany emulator to Rust. The key is:

1. **Learn first** - Invest in team training
2. **Start small** - Proof of concept with chat server
3. **Measure progress** - Regular benchmarks and metrics
4. **Stay flexible** - Adjust plan based on learnings
5. **Maintain safety** - Keep Java version running

**The migration is feasible and worthwhile if you have the time and commitment.**

Good luck! 🦀
