# Rust Translation Code Examples

This document provides practical code examples showing how to translate common Java patterns from the Aion Germany emulator to Rust.

## Table of Contents
1. [Networking Layer](#networking-layer)
2. [Packet Handling](#packet-handling)
3. [Database Operations](#database-operations)
4. [Game Entities](#game-entities)
5. [Event System](#event-system)
6. [Configuration](#configuration)
7. [Logging](#logging)

## Networking Layer

### Java (Current)
```java
// Java NIO Server
public class GameServer {
    private ServerSocketChannel serverChannel;
    private Selector selector;
    
    public void start() throws IOException {
        serverChannel = ServerSocketChannel.open();
        serverChannel.bind(new InetSocketAddress(7777));
        serverChannel.configureBlocking(false);
        
        selector = Selector.open();
        serverChannel.register(selector, SelectionKey.OP_ACCEPT);
        
        while (true) {
            selector.select();
            Iterator<SelectionKey> keys = selector.selectedKeys().iterator();
            
            while (keys.hasNext()) {
                SelectionKey key = keys.next();
                keys.remove();
                
                if (key.isAcceptable()) {
                    acceptConnection();
                } else if (key.isReadable()) {
                    readData(key);
                }
            }
        }
    }
}
```

### Rust (Tokio-based)
```rust
// Rust Tokio Server
use tokio::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::error::Error;

pub struct GameServer {
    port: u16,
    connection_handler: Arc<ConnectionHandler>,
}

impl GameServer {
    pub async fn start(&self) -> Result<(), Box<dyn Error>> {
        let listener = TcpListener::bind(format!("0.0.0.0:{}", self.port)).await?;
        println!("Game server listening on port {}", self.port);
        
        loop {
            match listener.accept().await {
                Ok((socket, addr)) => {
                    println!("New connection from: {}", addr);
                    let handler = Arc::clone(&self.connection_handler);
                    
                    // Spawn a task for each connection
                    tokio::spawn(async move {
                        if let Err(e) = handle_client(socket, handler).await {
                            eprintln!("Error handling client: {}", e);
                        }
                    });
                }
                Err(e) => eprintln!("Failed to accept connection: {}", e),
            }
        }
    }
}

async fn handle_client(
    mut socket: TcpStream,
    handler: Arc<ConnectionHandler>
) -> Result<(), Box<dyn Error>> {
    let (reader, writer) = socket.split();
    let mut client = GameClient::new(reader, writer);
    
    while let Some(packet) = client.read_packet().await? {
        handler.process_packet(&mut client, packet).await?;
    }
    
    Ok(())
}
```

## Packet Handling

### Java (Current)
```java
// Java Packet
public abstract class AionServerPacket {
    protected ByteBuffer buf;
    
    public final void write(Connection con) {
        buf = ByteBuffer.allocate(2 + 2);
        buf.putShort((short) 0);
        writeImpl(con);
        buf.flip();
    }
    
    protected abstract void writeImpl(Connection con);
}

public class SM_PLAYER_INFO extends AionServerPacket {
    private Player player;
    
    public SM_PLAYER_INFO(Player player) {
        this.player = player;
    }
    
    @Override
    protected void writeImpl(Connection con) {
        writeD(player.getObjectId());
        writeS(player.getName());
        writeC(player.getLevel());
        writeQ(player.getExp());
    }
}
```

### Rust (Bytes-based)
```rust
use bytes::{Buf, BufMut, BytesMut};
use std::error::Error;

// Packet trait
pub trait Packet {
    fn opcode(&self) -> u16;
    fn encode(&self, buf: &mut BytesMut) -> Result<(), Box<dyn Error>>;
}

// Player info packet
#[derive(Debug, Clone)]
pub struct PlayerInfoPacket {
    pub object_id: u32,
    pub name: String,
    pub level: u8,
    pub exp: u64,
}

impl Packet for PlayerInfoPacket {
    fn opcode(&self) -> u16 {
        0x01 // Example opcode
    }
    
    fn encode(&self, buf: &mut BytesMut) -> Result<(), Box<dyn Error>> {
        buf.put_u16(self.opcode());
        buf.put_u32(self.object_id);
        
        // Write string with length prefix
        let name_bytes = self.name.as_bytes();
        buf.put_u16(name_bytes.len() as u16);
        buf.put_slice(name_bytes);
        
        buf.put_u8(self.level);
        buf.put_u64(self.exp);
        
        Ok(())
    }
}

// Packet decoder
pub struct PacketDecoder;

impl PacketDecoder {
    pub fn decode(buf: &mut BytesMut) -> Result<Option<Box<dyn Packet>>, Box<dyn Error>> {
        if buf.len() < 2 {
            return Ok(None); // Need more data
        }
        
        let opcode = buf.get_u16();
        
        match opcode {
            0x01 => {
                if buf.len() < 4 + 2 + 1 + 8 {
                    return Ok(None);
                }
                
                let object_id = buf.get_u32();
                let name_len = buf.get_u16() as usize;
                
                if buf.len() < name_len + 1 + 8 {
                    return Ok(None);
                }
                
                let name = String::from_utf8(buf.split_to(name_len).to_vec())?;
                let level = buf.get_u8();
                let exp = buf.get_u64();
                
                Ok(Some(Box::new(PlayerInfoPacket {
                    object_id,
                    name,
                    level,
                    exp,
                })))
            }
            _ => Err(format!("Unknown opcode: {:#04x}", opcode).into()),
        }
    }
}
```

## Database Operations

### Java (Current)
```java
// Java DAO
public class PlayerDAO {
    private static final String SELECT_QUERY = 
        "SELECT * FROM players WHERE id = ?";
    
    public Player loadPlayer(int playerId) {
        Connection con = null;
        try {
            con = DatabaseFactory.getConnection();
            PreparedStatement stmt = con.prepareStatement(SELECT_QUERY);
            stmt.setInt(1, playerId);
            ResultSet rs = stmt.executeQuery();
            
            if (rs.next()) {
                Player player = new Player();
                player.setObjectId(rs.getInt("id"));
                player.setName(rs.getString("name"));
                player.setLevel(rs.getInt("level"));
                player.setExp(rs.getLong("exp"));
                return player;
            }
        } catch (SQLException e) {
            log.error("Failed to load player", e);
        } finally {
            DatabaseFactory.close(con);
        }
        return null;
    }
}
```

### Rust (sqlx-based)
```rust
use sqlx::{MySql, Pool, FromRow};
use std::error::Error;

// Player model
#[derive(Debug, Clone, FromRow)]
pub struct Player {
    pub id: u32,
    pub name: String,
    pub level: i32,
    pub exp: i64,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

// Player DAO
pub struct PlayerDao {
    pool: Pool<MySql>,
}

impl PlayerDao {
    pub fn new(pool: Pool<MySql>) -> Self {
        Self { pool }
    }
    
    // Load player by ID
    pub async fn load_player(&self, player_id: u32) -> Result<Option<Player>, Box<dyn Error>> {
        let player = sqlx::query_as!(
            Player,
            r#"
            SELECT id, name, level, exp, x, y, z
            FROM players
            WHERE id = ?
            "#,
            player_id
        )
        .fetch_optional(&self.pool)
        .await?;
        
        Ok(player)
    }
    
    // Save player
    pub async fn save_player(&self, player: &Player) -> Result<(), Box<dyn Error>> {
        sqlx::query!(
            r#"
            UPDATE players
            SET name = ?, level = ?, exp = ?, x = ?, y = ?, z = ?
            WHERE id = ?
            "#,
            player.name,
            player.level,
            player.exp,
            player.x,
            player.y,
            player.z,
            player.id
        )
        .execute(&self.pool)
        .await?;
        
        Ok(())
    }
    
    // Create new player
    pub async fn create_player(&self, name: &str) -> Result<u32, Box<dyn Error>> {
        let result = sqlx::query!(
            r#"
            INSERT INTO players (name, level, exp, x, y, z)
            VALUES (?, 1, 0, 0.0, 0.0, 0.0)
            "#,
            name
        )
        .execute(&self.pool)
        .await?;
        
        Ok(result.last_insert_id() as u32)
    }
    
    // Get all players online
    pub async fn get_online_players(&self) -> Result<Vec<Player>, Box<dyn Error>> {
        let players = sqlx::query_as!(
            Player,
            r#"
            SELECT id, name, level, exp, x, y, z
            FROM players
            WHERE online = 1
            "#
        )
        .fetch_all(&self.pool)
        .await?;
        
        Ok(players)
    }
}
```

## Game Entities

### Java (Current)
```java
// Java Entity hierarchy
public abstract class VisibleObject {
    private int objectId;
    private float x, y, z;
    
    public abstract void update(int deltaTime);
    public abstract void onDamage(int damage);
}

public class Npc extends VisibleObject {
    private NpcTemplate template;
    private int currentHp;
    private AiState aiState;
    
    @Override
    public void update(int deltaTime) {
        switch (aiState) {
            case IDLE:
                // Idle behavior
                break;
            case ATTACKING:
                // Attack behavior
                break;
        }
    }
    
    @Override
    public void onDamage(int damage) {
        currentHp -= damage;
        if (currentHp <= 0) {
            die();
        }
    }
}
```

### Rust (Trait-based)
```rust
use std::time::Duration;

// Entity trait
pub trait Entity {
    fn object_id(&self) -> u32;
    fn position(&self) -> (f32, f32, f32);
    fn set_position(&mut self, x: f32, y: f32, z: f32);
    fn update(&mut self, delta: Duration);
    fn on_damage(&mut self, damage: i32);
}

// AI state enum
#[derive(Debug, Clone, PartialEq)]
pub enum AiState {
    Idle,
    Patrolling {
        waypoints: Vec<(f32, f32, f32)>,
        current_waypoint: usize,
    },
    Attacking {
        target_id: u32,
    },
    Fleeing {
        escape_point: (f32, f32, f32),
    },
}

// NPC structure
#[derive(Debug, Clone)]
pub struct Npc {
    pub object_id: u32,
    pub template_id: u32,
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub current_hp: i32,
    pub max_hp: i32,
    pub ai_state: AiState,
}

impl Entity for Npc {
    fn object_id(&self) -> u32 {
        self.object_id
    }
    
    fn position(&self) -> (f32, f32, f32) {
        (self.x, self.y, self.z)
    }
    
    fn set_position(&mut self, x: f32, y: f32, z: f32) {
        self.x = x;
        self.y = y;
        self.z = z;
    }
    
    fn update(&mut self, delta: Duration) {
        match &mut self.ai_state {
            AiState::Idle => {
                // Check for nearby players
                // Switch to attacking if needed
            }
            AiState::Patrolling { waypoints, current_waypoint } => {
                let target = waypoints[*current_waypoint];
                let distance = calculate_distance(self.position(), target);
                
                if distance < 1.0 {
                    *current_waypoint = (*current_waypoint + 1) % waypoints.len();
                } else {
                    // Move towards waypoint
                    move_towards(&mut (self.x, self.y, self.z), target, delta);
                }
            }
            AiState::Attacking { target_id } => {
                // Attack logic
            }
            AiState::Fleeing { escape_point } => {
                // Flee logic
                move_towards(&mut (self.x, self.y, self.z), *escape_point, delta);
            }
        }
    }
    
    fn on_damage(&mut self, damage: i32) {
        self.current_hp -= damage;
        
        if self.current_hp <= 0 {
            self.die();
        } else if self.current_hp < self.max_hp / 4 {
            // Start fleeing if HP is low
            self.ai_state = AiState::Fleeing {
                escape_point: calculate_escape_point(self.position()),
            };
        }
    }
}

impl Npc {
    fn die(&mut self) {
        // Death logic
        println!("NPC {} has died", self.object_id);
        // Drop loot, give rewards, etc.
    }
}

// Helper functions
fn calculate_distance(pos1: (f32, f32, f32), pos2: (f32, f32, f32)) -> f32 {
    let dx = pos1.0 - pos2.0;
    let dy = pos1.1 - pos2.1;
    let dz = pos1.2 - pos2.2;
    (dx * dx + dy * dy + dz * dz).sqrt()
}

fn move_towards(current: &mut (f32, f32, f32), target: (f32, f32, f32), delta: Duration) {
    let speed = 5.0; // units per second
    let delta_secs = delta.as_secs_f32();
    let move_distance = speed * delta_secs;
    
    let direction = (
        target.0 - current.0,
        target.1 - current.1,
        target.2 - current.2,
    );
    
    let distance = (direction.0 * direction.0 + 
                   direction.1 * direction.1 + 
                   direction.2 * direction.2).sqrt();
    
    if distance > 0.0 {
        let normalized = (
            direction.0 / distance,
            direction.1 / distance,
            direction.2 / distance,
        );
        
        current.0 += normalized.0 * move_distance;
        current.1 += normalized.1 * move_distance;
        current.2 += normalized.2 * move_distance;
    }
}

fn calculate_escape_point(current: (f32, f32, f32)) -> (f32, f32, f32) {
    // Simple escape logic - move away from current position
    (current.0 + 50.0, current.1, current.2 + 50.0)
}
```

## Event System

### Java (Current)
```java
// Java Observer pattern
public interface GameEventListener {
    void handleEvent(GameEvent event);
}

public class PlayerEventListener implements GameEventListener {
    @Override
    public void handleEvent(GameEvent event) {
        if (event instanceof PlayerLoginEvent) {
            handlePlayerLogin((PlayerLoginEvent) event);
        }
    }
}
```

### Rust (Channel-based)
```rust
use tokio::sync::mpsc;
use std::collections::HashMap;

// Game events
#[derive(Debug, Clone)]
pub enum GameEvent {
    PlayerLogin { player_id: u32, name: String },
    PlayerLogout { player_id: u32 },
    PlayerMove { player_id: u32, x: f32, y: f32, z: f32 },
    PlayerDamage { player_id: u32, damage: i32 },
    NpcSpawn { npc_id: u32, template_id: u32 },
}

// Event bus
pub struct EventBus {
    sender: mpsc::UnboundedSender<GameEvent>,
    receiver: mpsc::UnboundedReceiver<GameEvent>,
}

impl EventBus {
    pub fn new() -> Self {
        let (sender, receiver) = mpsc::unbounded_channel();
        Self { sender, receiver }
    }
    
    pub fn subscribe(&self) -> mpsc::UnboundedSender<GameEvent> {
        self.sender.clone()
    }
    
    pub async fn process_events<F>(&mut self, mut handler: F)
    where
        F: FnMut(GameEvent),
    {
        while let Some(event) = self.receiver.recv().await {
            handler(event);
        }
    }
}

// Event handler example
pub struct PlayerEventHandler {
    online_players: HashMap<u32, String>,
}

impl PlayerEventHandler {
    pub fn new() -> Self {
        Self {
            online_players: HashMap::new(),
        }
    }
    
    pub fn handle_event(&mut self, event: GameEvent) {
        match event {
            GameEvent::PlayerLogin { player_id, name } => {
                println!("Player {} logged in: {}", player_id, name);
                self.online_players.insert(player_id, name);
            }
            GameEvent::PlayerLogout { player_id } => {
                if let Some(name) = self.online_players.remove(&player_id) {
                    println!("Player {} logged out: {}", player_id, name);
                }
            }
            GameEvent::PlayerMove { player_id, x, y, z } => {
                // Handle player movement
            }
            GameEvent::PlayerDamage { player_id, damage } => {
                println!("Player {} took {} damage", player_id, damage);
            }
            GameEvent::NpcSpawn { npc_id, template_id } => {
                println!("NPC {} spawned (template: {})", npc_id, template_id);
            }
        }
    }
}

// Usage
#[tokio::main]
async fn main() {
    let mut event_bus = EventBus::new();
    let event_sender = event_bus.subscribe();
    
    // Spawn event processor
    let mut handler = PlayerEventHandler::new();
    tokio::spawn(async move {
        event_bus.process_events(|event| {
            handler.handle_event(event);
        }).await;
    });
    
    // Send events
    event_sender.send(GameEvent::PlayerLogin {
        player_id: 1,
        name: "TestPlayer".to_string(),
    }).unwrap();
}
```

## Configuration

### Java (Current)
```java
// Java properties
public class Config {
    private static Properties props = new Properties();
    
    public static void load() {
        try (InputStream input = new FileInputStream("config/gameserver.properties")) {
            props.load(input);
        } catch (IOException e) {
            log.error("Failed to load config", e);
        }
    }
    
    public static int getInt(String key, int defaultValue) {
        return Integer.parseInt(props.getProperty(key, String.valueOf(defaultValue)));
    }
}
```

### Rust (config-based)
```rust
use serde::{Deserialize, Serialize};
use config::{Config, ConfigError, File};

#[derive(Debug, Deserialize, Serialize)]
pub struct GameServerConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub network: NetworkConfig,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct ServerConfig {
    pub name: String,
    pub max_players: u32,
    pub rate_xp: f32,
    pub rate_drop: f32,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct DatabaseConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub password: String,
    pub database: String,
    pub pool_size: u32,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct NetworkConfig {
    pub bind_address: String,
    pub port: u16,
    pub max_connections: u32,
}

impl GameServerConfig {
    pub fn load(path: &str) -> Result<Self, ConfigError> {
        let config = Config::builder()
            .add_source(File::with_name(path))
            .build()?;
        
        config.try_deserialize()
    }
}

// TOML config file example:
// [server]
// name = "Aion Germany"
// max_players = 2000
// rate_xp = 1.5
// rate_drop = 2.0
//
// [database]
// host = "localhost"
// port = 3306
// username = "aion"
// password = "password"
// database = "aion_gs"
// pool_size = 10
//
// [network]
// bind_address = "0.0.0.0"
// port = 7777
// max_connections = 2500
```

## Logging

### Java (Current)
```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class PlayerService {
    private static final Logger log = LoggerFactory.getLogger(PlayerService.class);
    
    public void login(Player player) {
        log.info("Player {} logged in", player.getName());
        log.debug("Player details: level={}, exp={}", player.getLevel(), player.getExp());
    }
}
```

### Rust (tracing-based)
```rust
use tracing::{info, debug, warn, error, instrument};

pub struct PlayerService {
    // ...
}

impl PlayerService {
    #[instrument(skip(self), fields(player_id = player.id))]
    pub async fn login(&self, player: &Player) -> Result<(), Box<dyn std::error::Error>> {
        info!(
            player_name = %player.name,
            level = player.level,
            "Player logged in"
        );
        
        debug!(
            exp = player.exp,
            position = ?(player.x, player.y, player.z),
            "Player details"
        );
        
        // ... login logic
        
        Ok(())
    }
    
    pub async fn handle_damage(&self, player: &mut Player, damage: i32) {
        warn!(
            player_id = player.id,
            damage = damage,
            hp_before = player.current_hp,
            "Player took damage"
        );
        
        player.current_hp -= damage;
        
        if player.current_hp <= 0 {
            error!(
                player_id = player.id,
                player_name = %player.name,
                "Player died"
            );
        }
    }
}

// Setup tracing subscriber
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

fn init_logging() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,aion_rust=debug".into())
        )
        .with(tracing_subscriber::fmt::layer())
        .init();
}
```

## Conclusion

These examples demonstrate that translating Java code to Rust is very feasible. Rust provides:
- **Better performance** through zero-cost abstractions
- **Memory safety** without garbage collection
- **Fearless concurrency** with compile-time guarantees
- **Modern tooling** with Cargo and the ecosystem

The patterns are different but often more elegant and type-safe in Rust.
