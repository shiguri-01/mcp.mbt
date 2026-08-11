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
      "https://as.example/.well-known/oauth-authorization-server/tenant", "https://as.example/tenant/.well-known/openid-configuration",
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
test "Bearer challenge handles quoted commas, escapes, and unknown fields" {
  let challenge = parse_bearer_challenge(
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
  let challenge = parse_bearer_challenge(
    "Basic realm=\"legacy\", Bearer resource_metadata=\"https://rs.example/meta\", scope=read",
  ) catch {
    _ => abort("Bearer challenge was not selected")
  }
  assert_eq(challenge.resource_metadata(), Some("https://rs.example/meta"))
  assert_eq(challenge.scope(), Some("read"))
}

///|
test "metadata issuer uses exact string comparison" {
  let value = Json::object({
    "issuer": "https://as.example/",
    "authorization_endpoint": "https://as.example/authorize",
    "token_endpoint": "https://as.example/token",
  })
  try
    ignore(
      parse_authorization_server_metadata(
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
  assert_eq(accepted.code(), "ok")
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
  assert_eq(credentials_cache.get("https://other.example"), None)
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
  let metadata = parse_authorization_server_metadata(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
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
  assert_eq(request.request_method(), Post)
  assert_eq(
    request.headers().get("authorization"),
    Some("Basic Y2xpZW50JTIwaWQ6cyUzQWVjcmV0"),
  )
  assert_true(
    request.body().contains("resource=https%3A%2F%2Frs.example%2Fmcp"[:]),
  )
}

///|
test "dynamic registration declares code flow and optional refresh grant" {
  let metadata = parse_authorization_server_metadata(
    Json::object({
      "issuer": "https://as.example",
      "authorization_endpoint": "https://as.example/authorize",
      "token_endpoint": "https://as.example/token",
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
  assert_eq(request.url(), "https://as.example/register")
  let body = @json.parse(request.body()) catch { _ => abort("invalid JSON") }
  guard body is Object(fields) else { abort("expected object") }
  assert_eq(
    fields.get("grant_types"),
    Some(Json::array(["authorization_code", "refresh_token"])),
  )
}

///|
async test "provider calls host functions without recursive method dispatch" {
  let provider = AuthorizationProvider(
    send_request=request => {
      HttpResponse(
        status=if request.url() == "https://as.example/metadata" {
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
    (provider.send(request) catch { _ => abort("send failed") }).status(),
    200,
  )
  assert_eq(
    provider.authorize("https://as.example/authorize?x=1") catch {
      _ => ""
    },
    "https://as.example/authorize?x=1&code=ok",
  )
  assert_eq(
    (provider.new_pkce_session() catch { _ => abort("PKCE failed") })
    .code_verifier()
    .length(),
    43,
  )
}

///|
async test "metadata discovery falls back from path-specific to origin-wide" {
  let requested : Array[String] = []
  let provider = AuthorizationProvider(
    send_request=request => {
      requested.push(request.url())
      if request.url() ==
        "https://rs.example/.well-known/oauth-protected-resource" {
        HttpResponse(
          status=200,
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
  assert_eq(metadata.resource(), "https://rs.example/mcp")
  assert_eq(requested, [
    "https://rs.example/.well-known/oauth-protected-resource/mcp", "https://rs.example/.well-known/oauth-protected-resource",
  ])
}
