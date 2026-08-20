///|
test "RFC discovery locations retain issuer and resource paths" {
  assert_eq(
    protected_resource_metadata_urls("https://Example.COM/mcp/") catch {
      _ => []
    },
    [
      "https://Example.COM/.well-known/oauth-protected-resource/mcp", "https://Example.COM/.well-known/oauth-protected-resource",
    ],
  )
  assert_eq(
    authorization_server_metadata_urls("https://as.example/tenant") catch {
      _ => []
    },
    [
      "https://as.example/.well-known/oauth-authorization-server/tenant", "https://as.example/.well-known/openid-configuration/tenant",
      "https://as.example/tenant/.well-known/openid-configuration",
    ],
  )
}

///|
test "resource identifiers retain path and query but ignore origin case" {
  assert_true(
    resource_identifiers_match(
      "HTTPS://API.Example/mcp/?tenant=a", "https://api.example/mcp?tenant=a",
    ) catch {
      _ => false
    },
  )
  assert_false(
    resource_identifiers_match(
      "https://api.example/mcp?tenant=a", "https://api.example/mcp?tenant=b",
    ) catch {
      _ => true
    },
  )
}

///|
test "protected-resource discovery retains a resource query only on the specific candidate" {
  assert_eq(
    protected_resource_metadata_urls("https://rs.example/mcp?tenant=a") catch {
      _ => []
    },
    [
      "https://rs.example/.well-known/oauth-protected-resource/mcp?tenant=a", "https://rs.example/.well-known/oauth-protected-resource",
    ],
  )
}

///|
test "authorization metadata requires HTTPS endpoints and PKCE S256" {
  let without_s256 = Json::object({
    "issuer": "https://as.example",
    "authorization_endpoint": "https://as.example/authorize",
    "token_endpoint": "https://as.example/token",
  })
  try
    ignore(
      AuthorizationServerMetadata::from_json(
        without_s256,
        expected_issuer="https://as.example",
      ),
    )
  catch {
    InvalidMetadata(_) => ()
    _ => fail("expected invalid metadata")
  } noraise {
    _ => fail("metadata without S256 must be rejected")
  }
  let insecure = Json::object({
    "issuer": "https://as.example",
    "authorization_endpoint": "http://as.example/authorize",
    "token_endpoint": "https://as.example/token",
    "code_challenge_methods_supported": ["S256"],
  })
  try
    ignore(
      AuthorizationServerMetadata::from_json(
        insecure,
        expected_issuer="https://as.example",
      ),
    )
  catch {
    InvalidUri(_) => ()
    _ => fail("expected invalid URI")
  } noraise {
    _ => fail("insecure authorization endpoint must be rejected")
  }
}

///|
test "PKCE verifier accepts only RFC 7636 unreserved characters" {
  try
    ignore(pkce_challenge("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!"))
  catch {
    AuthorizationFailed(_) => ()
    _ => fail("expected PKCE rejection")
  } noraise {
    _ => fail("invalid PKCE character must be rejected")
  }
}

///|
test "Bearer challenge handles quoted commas, escapes, and unknown fields" {
  let challenge = BearerChallenge::parse(
    "Bearer scope=\"read write\", resource_metadata=\"https://rs.example/meta?a=1,2\", x=\"a\\\"b\"",
  ) catch {
    _ => abort("valid challenge rejected")
  }
  assert_eq(challenge.scope(), Some("read write"))
  assert_eq(
    challenge.resource_metadata(),
    Some("https://rs.example/meta?a=1,2"),
  )
  assert_eq(challenge.parameter("X"), Some("a\"b"))
}

///|
test "Bearer challenge can follow another authentication scheme" {
  let challenge = BearerChallenge::parse(
    "Basic realm=\"legacy\", Bearer resource_metadata=\"https://rs.example/meta\", scope=read",
  ) catch {
    _ => abort("Bearer challenge was not selected")
  }
  assert_eq(challenge.resource_metadata(), Some("https://rs.example/meta"))
  assert_eq(challenge.scope(), Some("read"))
}

///|
test "Bearer auth parameters are case-insensitive and reject duplicates" {
  let challenge = BearerChallenge::parse(
    "Digest realm=\"legacy\", bEaReR ERROR = \"insufficient_scope\", SCOPE = \"read write\"",
  ) catch {
    _ => abort("valid mixed challenge rejected")
  }
  assert_eq(challenge.error(), Some("insufficient_scope"))
  assert_eq(challenge.scope(), Some("read write"))
  try ignore(BearerChallenge::parse("Bearer scope=read, SCOPE=write")) catch {
    InvalidChallenge(_) => ()
    _ => fail("expected invalid challenge")
  } noraise {
    _ => fail("duplicate Bearer parameter must be rejected")
  }
}

///|
test "challenge-list scanning never selects Bearer text inside a quoted realm" {
  let challenge = BearerChallenge::parse(
    "Basic realm=\"x Bearer resource_metadata=https://evil\", Bearer resource_metadata=\"https://good.example/meta\"",
  ) catch {
    _ => abort("valid Bearer list member rejected")
  }
  assert_eq(challenge.resource_metadata(), Some("https://good.example/meta"))
}

///|
test "Bearer parameters reject non-tchar names, token values, and controls" {
  for
    invalid in [
      "Bearer bad:name=value", "Bearer scope=read/../../write", "Bearer scope=\"read\rwrite\"",
      "Bearer scope=read\nInjected: value",
    ] {
    try ignore(BearerChallenge::parse(invalid)) catch {
      InvalidChallenge(_) => ()
      _ => fail("expected InvalidChallenge")
    } noraise {
      _ => fail("invalid challenge syntax was accepted")
    }
  }
}

///|
test "metadata issuer uses exact string comparison" {
  let value = Json::object({
    "issuer": "https://as.example/",
    "authorization_endpoint": "https://as.example/authorize",
    "token_endpoint": "https://as.example/token",
    "code_challenge_methods_supported": ["S256"],
  })
  try
    ignore(
      AuthorizationServerMetadata::from_json(
        value,
        expected_issuer="https://as.example",
      ),
    )
  catch {
    InvalidMetadata(_) => ()
    _ => fail("expected issuer mismatch")
  } noraise {
    _ => fail("expected issuer mismatch")
  }
}

///|
test "PKCE S256 matches RFC 7636 Appendix B" {
  assert_eq(
    pkce_challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") catch {
      _ => ""
    },
    "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  )
}

///|
test "authorization response enforces exact state and RFC 9207 issuer" {
  let accepted = validate_authorization_response(
    "https://client.example/cb?code=ok&state=s&iss=https%3A%2F%2Fas.example",
    expected_state="s",
    expected_issuer="https://as.example",
    issuer_parameter_required=true,
  ) catch {
    _ => abort("valid response rejected")
  }
  assert_eq(accepted.code, "ok")
  try
    ignore(
      validate_authorization_response(
        "https://client.example/cb?code=ok&state=wrong&iss=https%3A%2F%2Fas.example",
        expected_state="s",
        expected_issuer="https://as.example",
        issuer_parameter_required=true,
      ),
    )
  catch {
    InvalidAuthorizationResponse(_) => ()
    _ => fail("expected state mismatch")
  } noraise {
    _ => fail("expected state mismatch")
  }
  try
    ignore(
      validate_authorization_response(
        "https://client.example/cb?code=ok&state=s",
        expected_state="s",
        expected_issuer="https://as.example",
        issuer_parameter_required=true,
      ),
    )
  catch {
    InvalidAuthorizationResponse(_) => ()
    _ => fail("expected missing issuer rejection")
  } noraise {
    _ => fail("expected missing issuer rejection")
  }
}

///|
test "issuer mismatch is rejected before an authorization error is acted on" {
  try
    ignore(
      validate_authorization_response(
        "https://client.example/cb?error=access_denied&state=s&iss=https%3A%2F%2Fevil.example",
        expected_state="s",
        expected_issuer="https://as.example",
        issuer_parameter_required=true,
      ),
    )
  catch {
    InvalidAuthorizationResponse(message) =>
      assert_true(message.contains("issuer"[:]))
    _ => fail("issuer validation must precede the OAuth error")
  } noraise {
    _ => fail("mismatched issuer was accepted")
  }
}

///|
test "exact resource mode preserves a semantically significant trailing slash" {
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "code_challenge_methods_supported": ["S256"],
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let credentials = ClientCredentials(client_id="client") catch {
    _ => abort("credentials rejected")
  }
  let request = authorization_code_token_request(
    metadata,
    credentials,
    code="code",
    redirect_uri="https://client.example/cb",
    code_verifier="verifier",
    resource="https://rs.example/mcp/",
    exact_resource=true,
  ) catch {
    _ => abort("token request rejected")
  }
  assert_true(
    request.body.contains("resource=https%3A%2F%2Frs.example%2Fmcp%2F"[:]),
  )
  try
    ignore(
      ProtectedResourceMetadata::from_json(
        Json::object({
          "resource": "https://rs.example/mcp",
          "authorization_servers": ["https://as.example"],
        }),
        expected_resource="https://rs.example/mcp/",
        exact_resource=true,
      ),
    )
  catch {
    InvalidMetadata(_) => ()
    _ => fail("expected exact resource mismatch")
  } noraise {
    _ => fail("exact resource comparison stripped the trailing slash")
  }
}

///|
test "origin-wide PRM may name only the same-origin root resource" {
  let accepted = ProtectedResourceMetadata::from_json(
    Json::object({
      "resource": "https://rs.example",
      "authorization_servers": ["https://as.example"],
    }),
    expected_resource="https://rs.example/mcp",
    allow_same_origin_root=true,
  ) catch {
    _ => abort("same-origin root metadata rejected")
  }
  assert_eq(accepted.resource, "https://rs.example")
  for
    mismatched_resource in ["https://other.example", "https://rs.example/other"] {
    try
      ignore(
        ProtectedResourceMetadata::from_json(
          Json::object({
            "resource": mismatched_resource,
            "authorization_servers": ["https://as.example"],
          }),
          expected_resource="https://rs.example/mcp",
          allow_same_origin_root=true,
        ),
      )
    catch {
      InvalidMetadata(_) => ()
      _ => fail("expected resource mismatch")
    } noraise {
      _ => fail("non-root or cross-origin resource was accepted")
    }
  }
}

///|
async test "discovery rejects a 200 JSON body with a non-JSON Content-Type" {
  let provider = AuthorizationProvider(
    send_request=_ => {
      HttpResponse(
        status=200,
        headers=Map([("Content-Type", "text/plain")]),
        body=Json::object({
          "resource": "https://rs.example/mcp",
          "authorization_servers": ["https://as.example"],
        }).stringify(),
      )
    },
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
  )
  try
    ignore(
      discover_protected_resource_metadata(provider, "https://rs.example/mcp"),
    )
  catch {
    InvalidMetadata(_) => ()
    _ => fail("expected invalid metadata")
  } noraise {
    _ => fail("non-JSON Content-Type was accepted")
  }
}

///|
test "scope policy gates offline_access and preserves prior grants" {
  assert_eq(
    initial_scopes(
      resource_scopes=["read"],
      authorization_server_scopes=["read", "offline_access"],
      wants_refresh_token=true,
    ),
    ["read", "offline_access"],
  )
  assert_eq(step_up_scopes(["read"], "write read"), ["read", "write"])
}

///|
test "retry budget is isolated and capped at three" {
  let policy = RetryPolicy() catch { _ => abort("valid retry policy rejected") }
  for _ in 0..<3 {
    policy.record_attempt("https://rs.example/a", "tools/call") catch {
      _ => abort("attempt inside budget rejected")
    }
  }
  try policy.record_attempt("https://rs.example/a", "tools/call") catch {
    RetryLimitExceeded(_) => ()
    _ => fail("expected retry limit")
  } noraise {
    _ => fail("expected retry limit")
  }
  policy.record_attempt("https://rs.example/a", "resources/read") catch {
    _ => abort("separate operation budget missing")
  }
}

///|
test "credential and token caches are issuer and resource bound" {
  let credentials = ClientCredentials(client_id="client") catch {
    _ => abort("credentials rejected")
  }
  let credentials_cache = CredentialCache()
  credentials_cache.put(issuer="https://as.example", credentials)
  assert_true(credentials_cache.get("https://other.example") is None)
  let tokens = OAuthTokens(access_token="secret") catch {
    _ => abort("token rejected")
  }
  let token_cache = TokenCache()
  token_cache.put(
    issuer="https://as.example",
    resource="https://rs.example/a",
    tokens,
  )
  assert_true(
    token_cache.get(
      issuer="https://as.example",
      resource="https://rs.example/b",
    )
    is None,
  )
}

///|
test "token request uses selected client authentication and RFC 8707 resource" {
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "code_challenge_methods_supported": ["S256"],
      "token_endpoint_auth_methods_supported": ["client_secret_basic"],
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let credentials = ClientCredentials(
    client_id="client id",
    client_secret="s:ecret",
    token_endpoint_auth_method=ClientSecretBasic,
  ) catch {
    _ => abort("credentials rejected")
  }
  let request = authorization_code_token_request(
    metadata,
    credentials,
    code="abc",
    redirect_uri="https://client.example/cb",
    code_verifier="verifier",
    resource="HTTPS://RS.Example/mcp/",
  ) catch {
    _ => abort("request rejected")
  }
  assert_eq(request.request_method, Post)
  assert_eq(
    request.headers.get("authorization"),
    Some("Basic Y2xpZW50K2lkOnMlM0FlY3JldA=="),
  )
  assert_true(
    request.body.contains("resource=https%3A%2F%2Frs.example%2Fmcp"[:]),
  )
}

///|
test "dynamic registration declares code flow and optional refresh grant" {
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "code_challenge_methods_supported": ["S256"],
      "registration_endpoint": "https://as.example/register",
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let request = dynamic_registration_request(
    metadata,
    client_name="MoonBit MCP",
    redirect_uris=["https://client.example/callback"],
    wants_refresh_token=true,
  ) catch {
    _ => abort("registration request rejected")
  }
  assert_eq(request.url, "https://as.example/register")
  let body = @json.parse(request.body) catch { _ => abort("invalid JSON") }
  guard body is Object(fields) else { abort("expected object") }
  assert_eq(
    fields.get("grant_types"),
    Some(Json::array(["authorization_code", "refresh_token"])),
  )
  assert_eq(fields.get("application_type"), Some(Json::string("native")))
}

///|
test "pre-registered credentials take priority over client metadata and DCR" {
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "registration_endpoint": "https://as.example/register",
      "client_id_metadata_document_supported": true,
      "code_challenge_methods_supported": ["S256"],
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let credentials = ClientCredentials(client_id="registered") catch {
    _ => abort("credentials rejected")
  }
  let choice = choose_registration(
    metadata,
    client_id_metadata_url="https://client.example/metadata.json",
    pre_registered=credentials,
  ) catch {
    _ => abort("registration selection failed")
  }
  assert_true(choice is PreRegistered(_))
  try
    ignore(
      choose_registration(
        metadata,
        client_id_metadata_url="https://client.example/",
      ),
    )
  catch {
    UnsupportedRegistration(_) => ()
    _ => fail("expected unsupported registration")
  } noraise {
    _ => fail("root client metadata document URL was accepted")
  }
}

///|
test "token response retains a positive expires_in policy value" {
  let tokens = OAuthTokens::from_json(
    Json::object({
      "access_token": "access",
      "token_type": "Bearer",
      "expires_in": 60,
    }),
  ) catch {
    _ => abort("token response rejected")
  }
  assert_eq(tokens.expires_in, Some(60))
}

///|
async test "provider calls host functions without recursive method dispatch" {
  let provider = AuthorizationProvider(
    send_request=request => {
      HttpResponse(
        status=if request.url == "https://as.example/metadata" {
          200
        } else {
          500
        },
        body="{}",
      )
    },
    open_authorization_url=url => url + "&code=ok",
    random_bytes=size => Bytes::make(size, 7),
  )
  let request = HttpRequest(
    request_method=Get,
    url="https://as.example/metadata",
  ) catch {
    _ => abort("request rejected")
  }
  assert_eq(
    (provider.send(request) catch { _ => abort("send failed") }).status,
    200,
  )
  assert_eq(
    provider.authorize("https://as.example/authorize?x=1") catch {
      _ => ""
    },
    "https://as.example/authorize?x=1&code=ok",
  )
  assert_eq(
    (provider.new_pkce_session() catch { _ => abort("PKCE failed") }).code_verifier.length(),
    43,
  )
}

///|
async test "metadata discovery falls back from path-specific to origin-wide" {
  let requested : Array[String] = []
  let provider = AuthorizationProvider(
    send_request=request => {
      requested.push(request.url)
      if request.url ==
        "https://rs.example/.well-known/oauth-protected-resource" {
        HttpResponse(
          status=200,
          headers=Map([("Content-Type", "application/json; charset=utf-8")]),
          body=Json::object({
            "resource": "https://rs.example/mcp",
            "authorization_servers": ["https://as.example"],
          }).stringify(),
        )
      } else {
        HttpResponse(status=404)
      }
    },
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
  )
  let metadata = discover_protected_resource_metadata(
    provider, "https://rs.example/mcp",
  ) catch {
    _ => abort("metadata discovery failed")
  }
  assert_eq(metadata.resource, "https://rs.example/mcp")
  assert_eq(requested, [
    "https://rs.example/.well-known/oauth-protected-resource/mcp", "https://rs.example/.well-known/oauth-protected-resource",
  ])
}

///|
async test "refresh response omission preserves refresh token and granted scope" {
  let requests : Array[HttpRequest] = []
  let provider = AuthorizationProvider(
    send_request=request => {
      requests.push(request)
      HttpResponse(
        status=200,
        headers=Map([("content-type", "application/json")]),
        body=Json::object({
          "access_token": "new-access",
          "token_type": "Bearer",
        }).stringify(),
      )
    },
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
  )
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "code_challenge_methods_supported": ["S256"],
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let credentials = ClientCredentials(client_id="client") catch {
    _ => abort("credentials rejected")
  }
  let tokens = AuthorizationEngine(provider).refresh(
    metadata,
    credentials,
    refresh_token="bound-refresh",
    resource="https://rs.example/mcp",
    scopes=["read", "offline_access"],
  ) catch {
    _ => abort("refresh failed")
  }
  assert_eq(tokens.access_token, "new-access")
  assert_eq(tokens.refresh_token, Some("bound-refresh"))
  assert_eq(tokens.scope, ["read", "offline_access"])
  guard requests is [request] else { abort("expected one token request") }
  assert_true(request.body.contains("grant_type=refresh_token"[:]))
  assert_true(
    request.body.contains("resource=https%3A%2F%2Frs.example%2Fmcp"[:]),
  )
}

///|
async test "insecure loopback opt-in recognizes bracketed IPv6 with a port" {
  let provider = AuthorizationProvider(
    send_request=_ => HttpResponse(status=204),
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
    allow_insecure_loopback=true,
  )
  let response = provider.send(
    HttpRequest(request_method=Get, url="http://[::1]:9123/metadata") catch {
      _ => abort("valid IPv6 URI rejected")
    },
  ) catch {
    _ => abort("opted-in loopback request rejected")
  }
  assert_eq(response.status, 204)
}

///|
test "default destination policy denies reserved address literals" {
  let provider = AuthorizationProvider(
    send_request=_ => HttpResponse(status=204),
    open_authorization_url=url => url,
    random_bytes=size => Bytes::make(size, 1),
  )
  for
    destination in [
      "https://169.254.169.254/metadata", "https://127.0.0.2/token", "https://0.0.0.0/authorize",
      "https://[::ffff:127.0.0.1]/register",
    ] {
    try provider.check_destination(destination) catch {
      InvalidUri(_) => ()
      _ => fail("expected InvalidUri")
    } noraise {
      _ => fail("reserved address literal was accepted")
    }
  }
  provider.check_destination("https://auth.example/token") catch {
    _ => fail("public HTTPS destination was rejected")
  }
}

///|
test "DCR response omission preserves the requested token authentication method" {
  let credentials = ClientCredentials::from_registration_json(
    Json::object({
      "client_id": "dynamic-client",
      "client_secret": "server-issued-but-unused",
    }),
    requested_token_endpoint_auth_method=None,
  ) catch {
    _ => abort("valid DCR response rejected")
  }
  assert_eq(credentials.token_endpoint_auth_method, None)
  assert_eq(credentials.client_secret, Some("server-issued-but-unused"))
  let metadata = AuthorizationServerMetadata::from_json(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
      "token_endpoint_auth_methods_supported": ["none"],
      "code_challenge_methods_supported": ["S256"],
    }),
    expected_issuer="https://as.example",
  ) catch {
    _ => abort("metadata rejected")
  }
  let token_request = authorization_code_token_request(
    metadata,
    credentials,
    code="code",
    redirect_uri="https://client.example/callback",
    code_verifier="verifier",
    resource="https://rs.example/mcp",
  ) catch {
    _ => abort("none-auth token request rejected")
  }
  assert_true(token_request.headers.get("authorization") is None)
  assert_true(token_request.body.contains("client_id=dynamic-client"[:]))
  assert_false(token_request.body.contains("server-issued-but-unused"[:]))
}
