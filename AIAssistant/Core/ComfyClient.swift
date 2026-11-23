import Foundation
import UIKit

struct ComfyClient {
    enum ComfyError: LocalizedError {
        case badStatus(Int)
        case noPromptId
        case timeout
        case noImage

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "ComfyUI вернул ошибку \(code)"
            case .noPromptId: return "ComfyUI не принял задание"
            case .timeout: return "Генерация не завершилась вовремя"
            case .noImage: return "Не удалось прочитать изображение"
            }
        }
    }

    let base: String

    private var root: String {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: root + path) else { throw OllamaClient.ClientError.badBase }
        return url
    }

    func generate(prompt: String, checkpoint: String = "DreamShaper_8_pruned.safetensors") async throws -> UIImage {
        let seed = Int.random(in: 0..<2_000_000_000)
        let workflow: [String: Any] = [
            "1": ["class_type": "CheckpointLoaderSimple", "inputs": ["ckpt_name": checkpoint]],
            "2": ["class_type": "CLIPTextEncode", "inputs": ["text": prompt, "clip": ["1", 1]]],
            "3": [
                "class_type": "CLIPTextEncode",
                "inputs": [
                    "text": "low quality, worst quality, blurry, watermark, text, deformed, extra limbs",
                    "clip": ["1", 1]
                ]
            ],
            "4": ["class_type": "EmptyLatentImage", "inputs": ["width": 512, "height": 512, "batch_size": 1]],
            "5": [
                "class_type": "KSampler",
                "inputs": [
                    "model": ["1", 0],
                    "seed": seed,
                    "steps": 20,
                    "cfg": 7.0,
                    "sampler_name": "euler",
                    "scheduler": "normal",
                    "positive": ["2", 0],
                    "negative": ["3", 0],
                    "latent_image": ["4", 0],
                    "denoise": 1.0
                ]
            ],
            "6": ["class_type": "VAEDecode", "inputs": ["samples": ["5", 0], "vae": ["1", 2]]],
            "7": ["class_type": "SaveImage", "inputs": ["images": ["6", 0], "filename_prefix": "4MOVE"]]
        ]
        let payload: [String: Any] = ["prompt": workflow, "client_id": "4move-ios"]

        var request = URLRequest(url: try endpoint("/prompt"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ComfyError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promptId = json["prompt_id"] as? String else {
            throw ComfyError.noPromptId
        }

        let deadline = Date().addingTimeInterval(240)
        var imageURL: URL?

        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let historyURL = try endpoint("/history/" + promptId)
            guard let historyData = (try? await URLSession.shared.data(from: historyURL))?.0,
                  let rootJson = try? JSONSerialization.jsonObject(with: historyData) as? [String: Any],
                  let entry = rootJson[promptId] as? [String: Any],
                  let outputs = entry["outputs"] as? [String: Any],
                  let node = outputs["7"] as? [String: Any],
                  let images = node["images"] as? [[String: Any]],
                  let first = images.first,
                  let filename = first["filename"] as? String else { continue }

            let subfolder = first["subfolder"] as? String ?? ""
            let type = first["type"] as? String ?? "output"
            guard var components = URLComponents(url: try endpoint("/view"), resolvingAgainstBaseURL: false) else { continue }
            components.queryItems = [
                URLQueryItem(name: "filename", value: filename),
                URLQueryItem(name: "subfolder", value: subfolder),
                URLQueryItem(name: "type", value: type)
            ]
            imageURL = components.url
            break
        }

        guard let imageURL else { throw ComfyError.timeout }
        let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
        guard let http = imageResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: imageData) else { throw ComfyError.noImage }
        return image
    }
}
