#if OPENAI_ENABLED
@_exported @_spi(Internal) import OpenAIForFoundationModels
#endif
#if CLAUDE_ENABLED
@_exported @_spi(Internal) import ClaudeForFoundationModels
#endif
#if GOOGLE_ENABLED
@_exported @_spi(Internal) import GoogleForFoundationModels
#endif
