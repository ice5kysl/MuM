import AppKit

/// 更新包的一键下载（半自动升级的那一半）：DMG 下到临时目录，
/// 完成后由调用方挂载 —— 替换这最后一步留给用户拖一下，零新依赖。
///
/// 下载本身仍然是匿名 GET，和 UpdateChecker 一样不带任何用户标识。
enum UpdateDownloader {

    enum DownloadError: LocalizedError {
        case http(Int)
        case moved

        var errorDescription: String? {
            switch self {
            case .http(let code): return "下载失败（HTTP \(code)）"
            case .moved: return "下载完成但保存文件失败"
            }
        }
    }

    /// 下载到 `NSTemporaryDirectory()/MuM-<版本>.dmg`，重复下载直接覆盖同名文件。
    /// progress 回 0…1（分母未知时不回调）；completion 给落盘后的本地 URL。
    /// 两个回调都回主线程。
    static func download(
        _ url: URL,
        version: String,
        progress: @escaping @MainActor (Double) -> Void,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        let delegate = Delegate(progress: progress, completion: completion) { location in
            let ext = url.pathExtension.isEmpty ? "dmg" : url.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("MuM-\(version).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                return destination
            } catch {
                throw DownloadError.moved
            }
        }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("MuM/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request).resume()
    }

    /// 挂载 DMG 并打开安装盘窗口 —— NSWorkspace.open 对 .dmg 的语义就是
    /// 「挂载 + 在访达里显示」，正好是用户需要的下一步
    static func mountAndReveal(_ dmg: URL) {
        NSWorkspace.shared.open(dmg)
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate {
        let progress: @MainActor (Double) -> Void
        let completion: @MainActor (Result<URL, Error>) -> Void
        let move: (URL) throws -> URL

        init(progress: @escaping @MainActor (Double) -> Void,
             completion: @escaping @MainActor (Result<URL, Error>) -> Void,
             move: @escaping (URL) throws -> URL) {
            self.progress = progress
            self.completion = completion
            self.move = move
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let progress = self.progress
            DispatchQueue.main.async { progress(fraction) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            if let response = downloadTask.response as? HTTPURLResponse,
               response.statusCode != 200 {
                let completion = self.completion
                DispatchQueue.main.async { completion(.failure(DownloadError.http(response.statusCode))) }
                return
            }
            // location 是回调返回后就被系统清掉的临时文件，必须在这个方法里挪走
            let result: Result<URL, Error>
            do { result = .success(try move(location)) }
            catch { result = .failure(error) }
            let completion = self.completion
            DispatchQueue.main.async { completion(result) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didCompleteWithError error: (any Error)?) {
            guard let error else { return }
            let completion = self.completion
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }
}
