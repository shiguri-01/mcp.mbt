name = "shiguri-01/mcp"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/shiguri-01/mcp.mbt"

license = "Apache-2.0"

keywords = [ "mcp", "json-rpc", "model-context-protocol" ]

description = "Model Context Protocol library for MoonBit"

import {
  "moonbitlang/async@0.19.1",
  "shiguri-01/jsonrpc@0.2.0",
}

options(
  source: "src",
)
