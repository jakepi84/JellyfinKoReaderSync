# API Endpoints Documentation

## Base URL

All endpoints are prefixed with: `/plugins/koreader/v1`

For example, if your Jellyfin server is at `http://localhost:8096`, the full URL would be:
```
http://localhost:8096/plugins/koreader/v1/healthcheck
```

## Authentication

Most endpoints require authentication using KOReader's custom headers:

1. **Custom Headers** (KOReader format) - **Required**:
   - `x-auth-user`: Your Jellyfin username
   - `x-auth-key`: MD5 hash of your password (lowercase hex)

2. **HTTP Basic Authentication** - **Optional** (for enhanced security):
   - `Authorization: Basic <base64(username:password)>`

### Authentication Modes

The plugin supports two authentication modes:

1. **KOReader Headers Only** (Standard Mode):
   - Send only `x-auth-user` and `x-auth-key` headers
   - Compatible with KOReader's default configuration
   - Username must exist in Jellyfin
   - **Security Note**: This mode validates username existence but does not verify the password hash. Use appropriate network security measures (HTTPS, firewall) when using this mode.

2. **KOReader Headers + Basic Auth** (Enhanced Security):
   - Send both custom headers and Basic Authentication
   - Validates password against Jellyfin
   - Provides stronger authentication
   - **Recommended** for internet-facing servers

### Example Authentication

**Standard Mode (KOReader Headers Only):**
```bash
# Calculate MD5 hash of password
echo -n "mypassword" | md5sum
# Output: 34819d7beeabb9260a5c854bc85b3e44

# Make authenticated request
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 34819d7beeabb9260a5c854bc85b3e44" \
  http://localhost:8096/plugins/koreader/v1/users/auth
```

**Enhanced Security Mode (with Basic Auth):**
```bash
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 34819d7beeabb9260a5c854bc85b3e44" \
  -u myusername:mypassword \
  http://localhost:8096/plugins/koreader/v1/users/auth
```

## Endpoints

### 1. Health Check

Check if the plugin is running.

**URL:** `GET /plugins/koreader/v1/healthcheck`

**Authentication:** None required

**Response:**
```json
{
  "state": "OK"
}
```

**Example:**
```bash
curl http://localhost:8096/plugins/koreader/v1/healthcheck
```

---

### 2. Authenticate User

Verify user credentials.

**URL:** `GET /plugins/koreader/v1/users/auth`

**Authentication:** Required (KOReader headers, Basic auth optional)

**Response:**
```json
{
  "authorized": "OK"
}
```

**Example:**
```bash
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 34819d7beeabb9260a5c854bc85b3e44" \
  http://localhost:8096/plugins/koreader/v1/users/auth
```

---

### 3. Get Reading Progress

Retrieve stored reading progress for a document.

**URL:** `GET /plugins/koreader/v1/syncs/progress/{document}`

**Authentication:** Required (KOReader headers, Basic auth optional)

**URL Parameters:**
- `document` (string): Document identifier (MD5 hash from KOReader)

**Response (when progress exists):**
```json
{
  "document": "abc123def456789",
  "percentage": 0.45,
  "progress": "/body/DocFragment[20]/body/p[22]/img.0",
  "device": "PocketBook",
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": 1703289600
}
```

**Response (no progress found):**
```json
{}
```

**Example:**
```bash
curl -X GET \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 34819d7beeabb9260a5c854bc85b3e44" \
  http://localhost:8096/plugins/koreader/v1/syncs/progress/abc123def456789
```

---

### 4. Update Reading Progress

Store or update reading progress for a document.

**URL:** `PUT /plugins/koreader/v1/syncs/progress`

**Authentication:** Required (KOReader headers, Basic auth optional)

**Request Body:**
```json
{
  "document": "abc123def456789",
  "percentage": 0.45,
  "progress": "/body/DocFragment[20]/body/p[22]/img.0",
  "device": "PocketBook",
  "deviceId": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Request Fields:**
- `document` (string, required): Document identifier (MD5 hash)
- `percentage` (number, required): Reading progress as decimal (0.0 to 1.0)
- `progress` (string, required): KOReader position string
- `device` (string, required): Device name
- `deviceId` (string, optional): Unique device identifier

**Response:**
```json
{
  "document": "abc123def456789",
  "timestamp": 1703289600
}
```

**Example:**
```bash
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "x-auth-user: myusername" \
  -H "x-auth-key: 34819d7beeabb9260a5c854bc85b3e44" \
  -d '{
    "document": "abc123def456789",
    "percentage": 0.45,
    "progress": "/body/DocFragment[20]/body/p[22]/img.0",
    "device": "PocketBook",
    "deviceId": "550e8400-e29b-41d4-a716-446655440000"
  }' \
  http://localhost:8096/plugins/koreader/v1/syncs/progress
```

---

## Conflict Resolution

When the same book is updated from multiple devices:

1. Plugin compares `percentage` values
2. **Highest percentage wins** (furthest reading progress)
3. Server timestamp is updated to current time
4. Both devices will sync to the furthest position

**Example Scenario:**

- Device A syncs: 45% progress
- Device B syncs: 60% progress
- Result: Both devices will sync to 60%

---

## Error Responses

### 400 Bad Request
```json
{
  "message": "Invalid progress data: document field is required"
}
```

### 401 Unauthorized
```json
{
  "message": "Authentication failed"
}
```

### 500 Internal Server Error
```json
{
  "message": "Internal server error"
}
```

---

## Data Format

### Document Identifier

The document ID is an MD5 hash calculated by KOReader:
- **BINARY method** (default): MD5 of the first 16KB of the file content
- **FILENAME method**: MD5 of the full file path on device

**Plugin Matching:**
The Jellyfin plugin supports both methods and automatically tries multiple strategies:
1. Binary hash (MD5 of first 16KB) - matches KOReader's default
2. Filename with extension 
3. Filename without extension
4. Full Jellyfin path

This ensures maximum compatibility regardless of which method KOReader is configured to use.

### Percentage Format

Progress percentage is a decimal value between 0.0 and 1.0:
- `0.0` = 0% (start of book)
- `0.5` = 50% (halfway)
- `1.0` = 100% (end of book)

### Progress Position

The progress position is a KOReader-specific string that represents an exact location in the document. Format varies by document type (EPUB, PDF, etc.).

Example: `/body/DocFragment[20]/body/p[22]/img.0`

### Timestamp

Unix timestamp (seconds since epoch): `1703289600` = 2024-12-23 01:00:00 UTC

---

## Testing with curl

### Test Authentication
```bash
# Replace with your Jellyfin credentials
USERNAME="admin"
PASSWORD="admin"
PASSWORD_MD5=$(echo -n "$PASSWORD" | md5sum | cut -d' ' -f1)

curl -X GET \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  http://localhost:8096/plugins/koreader/v1/users/auth
```

### Test Progress Sync
```bash
# Update progress
curl -X PUT \
  -H "Content-Type: application/json" \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  -d '{
    "document": "test123",
    "percentage": 0.25,
    "progress": "/body/p[1]",
    "device": "TestDevice",
    "deviceId": "test-device-id"
  }' \
  http://localhost:8096/plugins/koreader/v1/syncs/progress

# Retrieve progress
curl -X GET \
  -H "x-auth-user: $USERNAME" \
  -H "x-auth-key: $PASSWORD_MD5" \
  http://localhost:8096/plugins/koreader/v1/syncs/progress/test123
```

---

## KOReader Configuration

In KOReader, configure the sync server with:

- **Server:** `http://your-jellyfin-server:8096/plugins/koreader/v1`
- **Username:** Your Jellyfin username
- **Password:** Your Jellyfin password
- **Document matching method:** Leave as **Binary** (default) for best compatibility

KOReader will automatically:
- Calculate MD5 hash of your password for the `x-auth-key` header
- Generate the document identifier using the configured method
- Send both custom headers and basic auth

**Note:** The plugin works with KOReader's default settings. No configuration changes are required for basic functionality.
