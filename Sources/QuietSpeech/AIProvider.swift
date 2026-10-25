import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    case openAI
    case groq
    case ollama
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .openAI: return "OpenAI"
        case .groq: return "Groq"
        case .ollama: return "Ollama"
        case .custom: return "Custom"
        }
    }

    var badgeName: String {
        switch self {
        case .apple: return "Apple"
        default: return name
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .apple: return ""
        case .openAI: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: return ""
        case .openAI: return "gpt-4.1-mini"
        case .groq: return "openai/gpt-oss-120b"
        case .ollama: return "llama3.2"
        case .custom: return ""
        }
    }

    var usesEndpoint: Bool { self != .apple }

    /// Providers with an OpenAI-compatible `/audio/transcriptions` endpoint.
    var supportsProviderTranscription: Bool {
        switch self {
        case .openAI, .groq, .custom: return true
        case .apple, .ollama: return false
        }
    }

    var defaultTranscriptionModel: String {
        switch self {
        case .openAI: return "whisper-1"
        case .groq: return "whisper-large-v3-turbo"
        case .custom: return "whisper-1"
        case .apple, .ollama: return ""
        }
    }
}

struct AIProviderConfig: Codable, Equatable {
    var endpoint: String
    var model: String
}
