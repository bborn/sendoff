Sendoff::Engine.routes.draw do
  post "/mcp", to: "mcp#handle"
end
