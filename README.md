# VanVyaapaar — Tribal Crafts E-Commerce Platform

> A production-grade e-commerce backend for tribal artisans, built with Spring Boot 3, featuring a geo-spatial delivery engine, event-driven architecture with Apache Kafka, real-time WebSocket tracking, and deployed on AWS with automated CI/CD.

---

## Architecture

![AWS Architecture](Architecture/Arch-dia.png)

---

## Backend Overview

The backend is a **Spring Boot 3 monolith** structured around three user roles — Admin, Seller, and Buyer — with a layered delivery system built on top. The delivery layer evolved in two phases: geo-spatial agent assignment using Redis, and event-driven order processing using Kafka.

**Tech Stack:**
- Java 17 + Spring Boot 3.5.6
- Spring Security + JWT (stateless auth)
- Spring Data JPA + MySQL 8 (Amazon RDS)
- Spring Data Redis + Jedis (geo-spatial indexing)
- Spring Kafka + Apache Kafka (event streaming)
- Spring WebSocket + STOMP (real-time updates)
- Razorpay SDK (payment gateway)
- Lombok + Bean Validation

---

## Package Structure

```
com.tribal/
├── config/
│   ├── RedisConfig.java          ← Jedis connection pool + RedisTemplate
│   ├── WebSocketConfig.java      ← STOMP broker + SockJS endpoint
│   ├── KafkaConfig.java          ← Producer/Consumer factory beans
│   ├── KafkaTopicConfig.java     ← Topic definitions (14 topics)
│   ├── KafkaHealthIndicator.java ← Actuator health check for Kafka
│   └── GeoProperties.java        ← Geo config (radius, stale timeout)
│
├── security/
│   ├── JwtUtil.java              ← Token generation + validation (JJWT)
│   ├── JwtAuthFilter.java        ← OncePerRequestFilter — extracts + validates JWT
│   └── SecurityConfig.java       ← Role-based route protection
│
├── model/                        ← JPA entities
│   ├── Base.java                 ← @SuperBuilder base (id, name, email, password, phone, address)
│   ├── Buyer.java                ← extends Base, has Orders + Cart
│   ├── Seller.java               ← extends Base, has approval status
│   ├── Admin.java                ← extends Base
│   ├── Product.java
│   ├── Order.java                ← OrderStatus enum, delivery address fields
│   ├── Cart.java
│   ├── Delivery.java             ← DeliveryStatus enum, agent FK, order FK
│   ├── DeliveryAgent.java        ← latitude, longitude, workload, vehicle type
│   ├── Payment.java
│   ├── Notification.java
│   ├── Review.java
│   ├── Wishlist.java
│   ├── Coupon.java
│   ├── Complaint.java
│   └── ServiceableArea.java
│
├── event/                        ← Kafka event schemas
│   ├── DeliveryEvent.java        ← Abstract base (eventType, correlationId, timestamp)
│   ├── OrderCreatedEvent.java
│   ├── OrderUpdatedEvent.java
│   ├── OrderCancelledEvent.java
│   ├── DeliveryCreatedEvent.java
│   ├── DeliveryAssignedEvent.java
│   ├── DeliveryPickedUpEvent.java
│   ├── DeliveryInTransitEvent.java
│   ├── DeliveryDeliveredEvent.java
│   ├── DeliveryCancelledEvent.java
│   ├── AgentLocationUpdatedEvent.java
│   ├── AgentStatusChangedEvent.java
│   ├── AgentAssignedEvent.java
│   └── AgentUnassignedEvent.java
│
├── service/
│   ├── GeoService.java           ← Redis GEOADD/GEORADIUS/GEODIST operations
│   ├── DeliveryService.java      ← Multi-radius agent assignment + scoring
│   ├── EventPublisher.java       ← Kafka publish with graceful degradation
│   ├── EventConsumer.java        ← @KafkaListener → WebSocket bridge
│   ├── WebSocketService.java     ← Channel-based broadcasting
│   ├── OrderStatusSyncService.java ← Bidirectional delivery↔order status sync
│   ├── PaymentConfirmationService.java ← Delivery creation after payment
│   ├── EmailNotificationService.java
│   ├── NotificationService.java
│   ├── BatchGeoService.java      ← Bulk agent location updates
│   ├── MetricsService.java       ← Performance counters
│   ├── BuyerService.java
│   ├── SellerService.java
│   ├── AdminService.java
│   ├── PaymentService.java       ← Razorpay order creation + verification
│   ├── ChatbotService.java
│   └── impl/                     ← All implementations
│
├── controller/                   ← 20 REST controllers
│   ├── AuthController.java       ← /api/auth/register, /login
│   ├── BuyerController.java      ← /api/buyer/**
│   ├── SellerController.java     ← /api/seller/**
│   ├── AdminController.java      ← /api/admin/**
│   ├── DeliveryController.java   ← /api/delivery/**
│   ├── DeliveryAgentController.java
│   ├── OrderDeliveryIntegrationController.java
│   ├── PaymentController.java    ← Razorpay webhook + verification
│   ├── HealthController.java     ← /api/health (Redis, WS, DB)
│   ├── MetricsController.java
│   ├── NotificationController.java
│   ├── ChatbotController.java
│   ├── BatchGeoController.java
│   └── WebSocketController.java
│
├── repository/                   ← 15 Spring Data JPA repositories
├── dto/                          ← Request/Response DTOs
├── exception/                    ← GlobalExceptionHandler
└── util/
    └── RetryUtil.java            ← Exponential backoff
```

---

## Delivery System — Phase 1: Geo-Spatial Engine

The core delivery problem: find the nearest available agent to a delivery location in under 100ms.

**Agent locations are indexed in Redis:**
```java
// GEOADD agents <lng> <lat> <agentId>
redisTemplate.opsForGeo().add("agents", new Point(lng, lat), "agent:" + agentId);
```

**On order placement, multi-radius search runs:**
```java
// Expands 5km → 10km → 15km until agents are found
for (double radius : List.of(5.0, 10.0, 15.0)) {
    GeoResults<RedisGeoCommands.GeoLocation<String>> results =
        redisTemplate.opsForGeo().radius("agents",
            new Circle(new Point(lng, lat), new Distance(radius, KILOMETERS)),
            GeoRadiusCommandArgs.newGeoRadiusArgs().includeDistance().sortAscending());
    if (!results.getContent().isEmpty()) break;
}
```

**Agents are scored before assignment:**
```
Score = (Distance × 0.4) + (Availability × 0.3) + (Rating × 0.2) + (Workload × 0.1)
```

**Circuit breaker — Redis unavailable → falls back to DB query:**
```java
try {
    return geoService.findNearbyAgents(lat, lng, radius);
} catch (RedisConnectionFailureException e) {
    log.warn("Redis unavailable, falling back to DB");
    return agentRepository.findAvailableAgents(pincode);
}
```

**Performance result:** Agent lookup dropped from 2000ms+ (DB pincode scan) to **<100ms** (Redis geo query).

---

## Delivery System — Phase 2: Event-Driven Architecture

Every meaningful delivery action now emits a domain event through Kafka, decoupling services and enabling async processing.

**14 Kafka topics across 4 domains:**
```
Order Events:    order.created | order.updated | order.cancelled
Delivery Events: delivery.created | delivery.assigned | delivery.picked-up |
                 delivery.in-transit | delivery.delivered | delivery.cancelled
Agent Events:    agent.location-updated | agent.status-changed |
                 agent.assigned | agent.unassigned
System Events:   delivery.dead-letter
```

**EventPublisher — graceful degradation when Kafka is down:**
```java
@Service
public class EventPublisherImpl implements EventPublisher {

    @Override
    public void publishEvent(DeliveryEvent event) {
        if (!kafkaEnabled) return;  // system continues without Kafka
        try {
            String topic = resolveTopicForEvent(event);
            kafkaTemplate.send(topic, event.getAggregateId(), event);
        } catch (Exception e) {
            log.error("Event publish failed — system continues: {}", e.getMessage());
        }
    }
}
```

**EventConsumer — Kafka → WebSocket bridge:**
```java
@KafkaListener(topics = "agent.location-updated", groupId = "vanvyaapaar-delivery-group")
public void handleAgentLocationUpdated(AgentLocationUpdatedEvent event) {
    webSocketService.sendToAgent(event.getAgentId(), "location_updated", event);
    webSocketService.sendToAdmins("agent_location_updated", event);
}

@KafkaListener(topics = "delivery.assigned")
public void handleDeliveryAssigned(DeliveryAssignedEvent event) {
    webSocketService.sendToBuyer(event.getBuyerId(), "delivery_assigned", event);
    webSocketService.sendToAgent(event.getAgentId(), "new_delivery", event);
}
```

**Order → Delivery event chain:**
```
Buyer places order
    → OrderCreatedEvent → order.created
        → EventConsumer creates Delivery
            → DeliveryCreatedEvent → delivery.created
                → GeoService finds nearest agent
                    → AgentAssignedEvent → delivery.assigned
                        → WebSocket broadcasts to Buyer + Agent + Admin
```

---

## Real-Time WebSocket Channels

```
/topic/buyer/{buyerId}    ← order status, delivery updates
/topic/agent/{agentId}    ← new assignments, location ack
/topic/delivery/{id}      ← live tracking updates
/topic/admin              ← system-wide monitoring
```

All channels use **STOMP over SockJS** with <50ms broadcast latency.

---

## Security

JWT-based stateless authentication with role-based route protection:

```java
// JwtAuthFilter extracts token → sets SecurityContext
// SecurityConfig enforces role boundaries:
.requestMatchers("/api/buyer/**").hasRole("BUYER")
.requestMatchers("/api/seller/**").hasRole("SELLER")
.requestMatchers("/api/admin/**").hasRole("ADMIN")
.requestMatchers("/api/delivery/**").hasAnyRole("BUYER", "SELLER", "ADMIN")
```

Passwords are BCrypt-hashed. JWT secret is externalized via environment variable (AWS Secrets Manager in production).

---

## Payment Flow

Razorpay integration with delivery creation gated on payment confirmation:

```
POST /api/payment/create-order   ← creates Razorpay order
POST /api/payment/verify         ← verifies signature
    → PaymentConfirmationService.onPaymentSuccess()
        → DeliveryService.createDelivery()   ← delivery only after payment
            → EventPublisher.publishEvent(OrderCreatedEvent)
```

---

## API Summary

| Domain | Base Path | Key Endpoints |
|---|---|---|
| Auth | `/api/auth` | `POST /register`, `POST /login` |
| Buyer | `/api/buyer` | cart, orders, wishlist, reviews, profile |
| Seller | `/api/seller` | products, orders, analytics, notifications |
| Admin | `/api/admin` | seller approval, user management, dashboard |
| Delivery | `/api/delivery` | create, assign, status update, tracking |
| Agent | `/api/delivery/agents` | register, location update, availability |
| Payment | `/api/payment` | Razorpay order creation + verification |
| Health | `/api/health` | Redis, WebSocket, DB, Kafka status |

---

## AWS Infrastructure

Infrastructure is defined as code in CloudFormation — single command deploys the full production environment.

| Service | Role |
|---|---|
| **EC2 + Auto Scaling** | Frontend (nginx) and Backend (Spring Boot) with auto scaling |
| **Application Load Balancer** | Routes `/auth/*`, `/buyer/*`, `/seller/*`, `/admin/*` → backend; `/*` → frontend |
| **RDS MySQL** | Managed database in private subnet |
| **S3 + CloudFront** | Product image storage + global CDN |
| **Secrets Manager** | RDS credentials — never hardcoded |
| **CodePipeline** | `git push` → build → deploy, fully automated |

## Traffic Flow

```
User Browser
│
▼
Application Load Balancer  ←──  CloudFront (product images via S3)
│
├── /auth, /buyer, /seller, /admin  ──►  Backend EC2 (Spring Boot :8080)
│                                               │
│                                               ▼
│                                         RDS MySQL (private subnet)
│
└── /*  ──►  Frontend EC2 (nginx :80 → React SPA)
```

## Scale Down (Cost Saving)

```powershell
aws autoscaling update-auto-scaling-group --auto-scaling-group-name vanvyaapaar-prod-FrontendASG-LTbPpCvjkvzN --min-size 0 --desired-capacity 0 --region us-east-1
aws autoscaling update-auto-scaling-group --auto-scaling-group-name vanvyaapaar-prod-BackendASG-4JT22BOEQJiO --min-size 0 --desired-capacity 0 --region us-east-1
```

## Scale Up (Bring Back)

```powershell
aws autoscaling update-auto-scaling-group --auto-scaling-group-name vanvyaapaar-prod-FrontendASG-LTbPpCvjkvzN --min-size 1 --desired-capacity 1 --region us-east-1
aws autoscaling update-auto-scaling-group --auto-scaling-group-name vanvyaapaar-prod-BackendASG-4JT22BOEQJiO --min-size 1 --desired-capacity 1 --region us-east-1
git commit --allow-empty -m "Bring up" && git push origin main
```

---

## Running Locally

**Prerequisites:** Java 17, MySQL 8, Redis, (optional) Kafka

```bash
# Clone and configure
git clone <repo>
cd vanpaayaar-backend

# Set DB credentials in application.properties
# Then run
./mvnw spring-boot:run
```

**With Docker (full stack):**
```bash
docker-compose up
```

Backend starts on `http://localhost:8080`

---

## Default Admin

| Field | Value |
|---|---|
| Email | admin@vanvyaapaar.com |
| Password | admin123 |
