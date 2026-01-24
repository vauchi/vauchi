# Problem: Relay connection leak causes capacity exhaustion

## Status: done

## Problem Statement

The relay server accumulates connections until hitting max capacity (1000), after which it rejects all new connections including health checks. This causes the relay to appear unhealthy and return 502 errors via kamal-proxy.

**Error observed:**
```
Connection rejected from 127.0.0.1:xxxxx: at max capacity (1000/1000)
```

The connections from 127.0.0.1 are likely health checks from kamal-proxy that aren't being closed properly.

## Origin

- **Source**: Production incident during P7 pre-production work
- **Date Created**: 2026-01-23
- **Discovered by**: Checking relay.vauchi.app health, found 502 Bad Gateway

## Impact

- **Severity**: HIGH (production service degradation)
- Relay becomes unresponsive after accumulating 1000 connections
- Health checks fail, triggering 502 errors
- Requires manual restart to recover
- Time to failure: ~19 hours based on observed incident

## Technical Analysis

### Observations

1. All 1000 connections from `127.0.0.1` (localhost/health checks)
2. Connections not being closed after health check response
3. Idle timeout (300s) not cleaning up these connections
4. kamal-proxy sends health checks every ~30 seconds

### Hypotheses

1. **HTTP health check on WebSocket port**: Health checks may be hitting the WebSocket endpoint (8080) instead of the HTTP endpoint, causing protocol mismatch
2. **Keep-alive without timeout**: HTTP keep-alive connections not being closed
3. **WebSocket upgrade not completing**: Partial WebSocket handshakes staying open
4. **Idle timeout not triggering**: Connections may be receiving periodic data preventing idle cleanup

### Investigation Steps

- [ ] Check kamal-proxy health check configuration (which port/path?)
- [ ] Review relay connection handling code for cleanup
- [ ] Add connection state logging to identify leak source
- [ ] Test with explicit connection close after health response
- [ ] Verify idle timeout is working correctly

## Artifacts

- [ ] Investigation document
- [ ] Root cause analysis
- [ ] Implementation plan
- [ ] Retrospective

## Root Cause

The HTTP health check handler on the WebSocket port (8080) used `try_write()` which is non-blocking and doesn't guarantee data is sent. The TCP connection was not properly closed after writing the response, causing connections to linger indefinitely.

## Fix

Changed HTTP response handling to:
1. Use `write_all().await` instead of `try_write()` for guaranteed delivery
2. Call `stream.shutdown().await` to properly close the TCP connection
3. Reduced logging verbosity for health checks (debug level instead of info)

**Commit**: relay/src/main.rs - proper async write and shutdown for HTTP responses

## Workaround (obsolete)

Restart the relay container:
```bash
ssh vauchi@87.106.25.46 "docker restart vauchi-relay-web-<id>"
```

## Related

- P7 Pre-Production Checklist: `planning/todo/2026-01-22-P7-pre-production-checklist.md`
- Relay deployment: `relay/deploy/DEPLOYMENT.md`
- Relay source: `relay/src/`
