import Foundation
import Photos

@MainActor
final class PhotoLibraryService {
    private let albumName = "NX3000"

    func saveAsset(at fileURL: URL, type: MediaAssetType) async throws {
        let session = try await prepareBatchSession()
        try await session.saveAsset(at: fileURL, type: type)
    }

    func prepareBatchSession() async throws -> PhotoLibraryBatchSession {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard authorization == .authorized || authorization == .limited else {
            throw NX3000Error.photoLibraryAccessDenied
        }

        let album = try await fetchOrCreateAlbum()
        return PhotoLibraryBatchSession(album: album, service: self)
    }

    fileprivate func saveFile(_ fileURL: URL, to album: PHAssetCollection, type: MediaAssetType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                switch type {
                case .image:
                    creationRequest.addResource(with: .photo, fileURL: fileURL, options: nil)
                case .video:
                    creationRequest.addResource(with: .video, fileURL: fileURL, options: nil)
                }

                guard let placeholder = creationRequest.placeholderForCreatedAsset,
                      let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                    return
                }

                albumChangeRequest.addAssets([placeholder] as NSArray)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: NX3000Error.photoLibrarySaveFailed(error.localizedDescription))
                    return
                }
                guard success else {
                    continuation.resume(throwing: NX3000Error.photoLibrarySaveFailed("The Photos operation did not finish successfully."))
                    return
                }
                continuation.resume(returning: ())
            })
        }
    }

    private func fetchOrCreateAlbum() async throws -> PHAssetCollection {
        if let existing = existingAlbum() {
            return existing
        }

        let localIdentifier: String = try await withCheckedThrowingContinuation { continuation in
            var placeholderIdentifier: String?
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                placeholderIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: NX3000Error.photoLibrarySaveFailed(error.localizedDescription))
                    return
                }
                guard success, let placeholderIdentifier else {
                    continuation.resume(throwing: NX3000Error.photoLibrarySaveFailed("Album creation did not complete."))
                    return
                }
                continuation.resume(returning: placeholderIdentifier)
            })
        }

        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let album = result.firstObject else {
            throw NX3000Error.photoLibrarySaveFailed("The NX3000 album could not be fetched after creation.")
        }
        return album
    }

    private func existingAlbum() -> PHAssetCollection? {
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var foundAlbum: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == self.albumName {
                foundAlbum = collection
                stop.pointee = true
            }
        }
        return foundAlbum
    }
}

@MainActor
final class PhotoLibraryBatchSession {
    private let album: PHAssetCollection
    private unowned let service: PhotoLibraryService

    init(album: PHAssetCollection, service: PhotoLibraryService) {
        self.album = album
        self.service = service
    }

    func saveAsset(at fileURL: URL, type: MediaAssetType) async throws {
        try await service.saveFile(fileURL, to: album, type: type)
    }
}
