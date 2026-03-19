# Summer Security — KeycloakException Error Mapping

`KeycloakException` extends `ViewableException`. Comprehensive auto-mapping added in **0.2.3** (~58 cases; pre-0.2.3 had ~5).

## Full Error Mapping Table

| Keycloak Error | Code | Status |
|---|---|---|
| `"Account disabled"` | `keycloak.account.disabled` | 400 |
| `"Invalid user credentials"` | `keycloak.authentication.failed` | 401 |
| `"Account is not fully set up"` | `keycloak.account.not.setup` | 400 |
| `"Session not active"` | `keycloak.session.inactive` | 401 |
| `"Token is not active"` | `keycloak.token.inactive` | 401 |
| `"Invalid username or password"` | `keycloak.authentication.failed` | 401 |
| `"Invalid user"` | `keycloak.user.invalid` | 401 |
| `"User not found"` | `keycloak.user.not.found` | 401 |
| `"User is disabled"` | `keycloak.user.disabled` | 403 |
| `"User is temporarily disabled"` | `keycloak.user.temporarily.disabled` | 403 |
| `"User account is locked"` | `keycloak.user.locked` | 403 |
| `"User must verify email"` | `keycloak.user.email.verification.required` | 400 |
| `"User email not verified"` | `keycloak.user.email.not.verified` | 400 |
| `"User must update password"` | `keycloak.user.password.update.required` | 400 |
| `"User must configure OTP"` | `keycloak.user.otp.required` | 400 |
| `"User must update profile"` | `keycloak.user.profile.update.required` | 400 |
| `"Session expired"` | `keycloak.session.expired` | 401 |
| `"User session not found"` | `keycloak.session.not.found` | 401 |
| `"Invalid session"` | `keycloak.session.invalid` | 401 |
| `"Invalid token"` | `keycloak.token.invalid` | 401 |
| `"Token signature invalid"` | `keycloak.token.signature.invalid` | 401 |
| `"Token expired"` | `keycloak.token.expired` | 401 |
| `"Access token expired"` | `keycloak.token.access.expired` | 401 |
| `"Refresh token expired"` | `keycloak.token.refresh.expired` | 401 |
| `"Invalid refresh token"` | `keycloak.token.refresh.invalid` | 401 |
| `"Refresh token reused"` | `keycloak.token.refresh.reused` | 401 |
| `"Invalid bearer token"` | `keycloak.token.bearer.invalid` | 401 |
| `"Bearer token not provided"` | `keycloak.token.missing` | 401 |
| `"Invalid client credentials"` | `keycloak.client.credentials.invalid` | 401 |
| `"Invalid client or invalid client credentials"` | `keycloak.client.credentials.invalid` | 401 |
| `"Client authentication failed"` | `keycloak.client.authentication.failed` | 401 |
| `"Client not found"` | `keycloak.client.not.found` | 404 |
| `"Client disabled"` | `keycloak.client.disabled` | 403 |
| `"Client secret not provided"` | `keycloak.client.secret.missing` | 400 |
| `"Invalid client secret"` | `keycloak.client.secret.invalid` | 401 |
| `"Client not allowed for direct access grants"` | `keycloak.client.direct.grant.disabled` | 403 |
| `"Invalid parameter: redirect_uri"` | `keycloak.request.redirect.invalid` | 400 |
| `"Invalid redirect_uri"` | `keycloak.request.redirect.invalid` | 400 |
| `"Missing parameter: grant_type"` | `keycloak.request.grant.missing` | 400 |
| `"Invalid request"` | `keycloak.request.invalid` | 400 |
| `"Invalid scope"` | `keycloak.scope.invalid` | 400 |
| `"Invalid response_type"` | `keycloak.response.type.invalid` | 400 |
| `"Invalid response_mode"` | `keycloak.response.mode.invalid` | 400 |
| `"Invalid code"` / `"Code not valid"` | `keycloak.authorization.code.invalid` | 400 |
| `"PKCE code verifier invalid"` | `keycloak.pkce.verifier.invalid` | 400 |
| `"PKCE verification failed"` | `keycloak.pkce.verification.failed` | 400 |
| `"Authentication failed"` | `keycloak.authentication.failed` | 401 |
| `"Identity provider login failure"` | `keycloak.identity.provider.failure` | 401 |
| `"Brokered identity provider error"` | `keycloak.identity.provider.broker.error` | 401 |
| `"User already exists"` | `keycloak.user.already.exists` | 409 |
| `"Email already exists"` | `keycloak.email.already.exists` | 409 |
| `"Invalid username"` | `keycloak.username.invalid` | 400 |
| _(unknown)_ | `<errorDescription>` | 500 |

## ReactiveKeycloakClient — Full Resource API

### ReactiveUsersResource

| Method | Return | Description |
|---|---|---|
| `create(UserRepresentation)` | `Mono<String>` | Returns userId from Location header |
| `list(Integer first, Integer max)` | `Flux<UserRepresentation>` | Paginated list |
| `search(String username, Boolean exact)` | `Flux<UserRepresentation>` | Search by username |
| `count()` | `Mono<Integer>` | Total user count |
| `get(String id)` | `ReactiveUserResource` | Sub-resource for single user |

### ReactiveUserResource

| Method | Return | Description |
|---|---|---|
| `toRepresentation()` | `Mono<UserRepresentation>` | Get user details |
| `update(UserRepresentation)` | `Mono<Void>` | Update user |
| `remove()` | `Mono<Void>` | Delete user |
| `resetPassword(CredentialRepresentation)` | `Mono<Void>` | Reset password |
| `logout()` | `Mono<Void>` | Logout all sessions |

### ReactiveClientsResource

| Method | Return | Description |
|---|---|---|
| `create(ClientRepresentation)` | `Mono<String>` | Returns client UUID |
| `findAll()` | `Flux<ClientRepresentation>` | List all clients |
| `findByClientId(String)` | `Flux<ClientRepresentation>` | Search by clientId |
| `get(String id)` | `ReactiveClientResource` | Sub-resource for single client |

### ReactiveClientResource

| Method | Return | Description |
|---|---|---|
| `toRepresentation()` | `Mono<ClientRepresentation>` | Get client details |
| `update(ClientRepresentation)` | `Mono<Void>` | Update client |
| `roles()` | `ReactiveRolesResource` | Client role management |

### ReactiveRolesResource

| Method | Return | Description |
|---|---|---|
| `list()` | `Flux<RoleRepresentation>` | List client roles |
| `create(RoleRepresentation)` | `Mono<Void>` | Create client role |

### ReactiveTokenResource (no admin auth)

| Method | Return | Description |
|---|---|---|
| `grantToken(String user, String pass)` | `Mono<AccessTokenResponse>` | Password grant |
| `refreshToken(String refreshToken)` | `Mono<AccessTokenResponse>` | Refresh token |
| `clientCredentials(String clientId, String secret, String scope)` | `Mono<AccessTokenResponse>` | Client credentials |
| `introspect(String token)` | `Mono<Map<String,Object>>` | Token introspection |
| `userInfo(String accessToken)` | `Mono<Map<String,Object>>` | UserInfo endpoint |
| `logout(String refreshToken)` | `Mono<Void>` | Logout via refresh token |

### DTOs

Uses `org.keycloak.representations.idm.*`: `UserRepresentation`, `ClientRepresentation`, `RoleRepresentation`, `CredentialRepresentation`, `AccessTokenResponse`.

## Role Synchronizer Details

`KeycloakRoleSynchronizer` (`ApplicationRunner`):

1. `RoleDefinitionScanner` scans `@AuthRoles` beans -> `List<ScannedResource(clientId, resourceDef, roles)>`
2. For each resource: finds or creates Keycloak client
3. Syncs roles (creates missing ones)
4. Syncs features (stored as JSON in client `features` attribute)
5. Syncs custom attributes (from `@AttributeDef`)

In 0.2.3+, `RoleDefinitionScanner` is registered as a Spring bean (injectable without role sync being active).
