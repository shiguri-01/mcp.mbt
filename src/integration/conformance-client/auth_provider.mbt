///|
async fn send_auth_request(
  request : @auth.HttpRequest,
) -> @auth.HttpResponse raise @auth.AuthError {
  let headers = request.headers
  match request.request_method {
    @auth.Get => {
      let (response, stream) = @async_http.get_stream(request.url, headers~) catch {
        error => raise @auth.TransportFailure(error.to_string())
      }
      defer stream.close()
      let body = stream.read_all().text() catch {
          error => raise @auth.TransportFailure(error.to_string())
        }
      @auth.HttpResponse(status=response.code, headers=response.headers, body~)
    }
    @auth.Post => {
      let body_bytes = @utf8.encode(request.body)
      headers["Content-Length"] = body_bytes.length().to_string()
      let stream = @async_http.post_stream(request.url, headers~) catch {
        error => raise @auth.TransportFailure(error.to_string())
      }
      defer stream.close()
      stream.write(body_bytes) catch {
        error => raise @auth.TransportFailure(error.to_string())
      }
      let response = stream.end_request() catch {
        error => raise @auth.TransportFailure(error.to_string())
      }
      let response_body = stream.read_all().text() catch {
          error => raise @auth.TransportFailure(error.to_string())
        }
      @auth.HttpResponse(
        status=response.code,
        headers=response.headers,
        body=response_body,
      )
    }
  }
}

///|
async fn follow_authorization_redirect(
  authorization_url : String,
) -> String raise @auth.AuthError {
  ignore(@auth.AbsoluteUri::parse(authorization_url))
  // MoonBit's native Windows socket reader currently panics when the runner
  // closes a 302 response. Use the platform HTTP utility for the fixture's
  // browser seam; OAuth policy and callback validation remain in the SDK.
  let (exit_code, output) = @process.collect_stdout("curl", [
    "--silent", "--show-error", "--include", "--max-redirs", "0", authorization_url,
  ]) catch {
    error => raise @auth.TransportFailure(error.to_string())
  }
  if exit_code != 0 {
    raise @auth.TransportFailure(
      "authorization user-agent exited with code \{exit_code}",
    )
  }
  let response = output.text() catch {
    error => raise @auth.TransportFailure(error.to_string())
  }
  let mut status_redirect = false
  let mut location : String? = None
  for index, raw_line in response.split("\r\n") {
    let line = raw_line.trim()
    if index == 0 {
      status_redirect = line.has_prefix("HTTP/1.1 3"[:]) ||
        line.has_prefix("HTTP/1.0 3"[:])
    } else if line.to_lower().has_prefix("location:"[:]) {
      location = Some(line[9:].trim().to_owned())
    }
  }
  guard status_redirect && location is Some(location) else {
    raise @auth.AuthorizationFailed(
      "authorization endpoint did not return a redirect callback",
    )
  }
  location
}

///|
fn fixture_random_source() -> (Int) -> Bytes raise @auth.AuthError {
  let now = @async.now().to_int()
  let seed_values : Array[Byte] = [
    for index in 0..<32 => {
      let shift = index % 4 * 8
      ((now >> shift) + index * 29).to_byte()
    }
  ]
  let generator = @random.Rand::chacha8(seed=Bytes::from_array(seed_values))
  size => {
    if size < 0 {
      raise @auth.TransportFailure("random byte count must not be negative")
    }
    Bytes::from_array(
      [
        for _ in 0..<size => {
          generator.uint(limit=256U).reinterpret_as_int().to_byte()
        }
      ],
    )
  }
}

///|
fn auth_error_message(error : @auth.AuthError) -> String {
  match error {
    @auth.InvalidUri(message)
    | @auth.InvalidChallenge(message)
    | @auth.InvalidMetadata(message)
    | @auth.InvalidAuthorizationResponse(message)
    | @auth.UnsupportedRegistration(message)
    | @auth.TransportFailure(message)
    | @auth.AuthorizationFailed(message)
    | @auth.RetryLimitExceeded(message) => message
  }
}

///|
fn conformance_authorization_provider() -> @auth.AuthorizationProvider {
  @auth.AuthorizationProvider(
    send_request=send_auth_request,
    open_authorization_url=follow_authorization_redirect,
    random_bytes=fixture_random_source(),
    allow_insecure_loopback=true,
  )
}
