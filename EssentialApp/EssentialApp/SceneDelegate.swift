//
//  Copyright © 2019 Essential Developer. All rights reserved.
//

import UIKit
import CoreData
import Combine
import EssentialFeed

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?
	
	private lazy var httpClient: HTTPClient = {
		URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))
	}()
	
	private lazy var store: FeedStore & FeedImageDataStore = {
		try! CoreDataFeedStore(
			storeURL: NSPersistentContainer
				.defaultDirectoryURL()
				.appendingPathComponent("feed-store.sqlite"))
	}()

	private lazy var baseURL = URL(string: "https://ile-api.essentialdeveloper.com/essential-feed")!
	
	private lazy var remoteFeedLoader: RemoteLoader = {
		RemoteLoader(
			url: baseURL.appendingPathComponent("/v1/feed"),
			client: httpClient,
			mapper: FeedItemsMapper.map)
	}()
	
	private lazy var localFeedLoader: LocalFeedLoader = {
		LocalFeedLoader(store: store, currentDate: Date.init)
	}()
	
	private lazy var remoteImageLoader: RemoteFeedImageDataLoader = {
		RemoteFeedImageDataLoader(client: httpClient)
	}()
	
	private lazy var localImageLoader: LocalFeedImageDataLoader = {
		LocalFeedImageDataLoader(store: store)
	}()

	private lazy var navigationController = UINavigationController(
		rootViewController: FeedUIComposer.feedComposedWith(
			feedLoader: makeRemoteFeedLoaderWithLocalFallback,
			imageLoader: makeLocalImageLoaderWithRemoteFallback,
			selection: showComments))
	
	convenience init(httpClient: HTTPClient, store: FeedStore & FeedImageDataStore) {
		self.init()
		self.httpClient = httpClient
		self.store = store
	}
	
	func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
		guard let scene = (scene as? UIWindowScene) else { return }
		
		window = UIWindow(windowScene: scene)
		configureWindow()
	}

	private func showComments(for image: FeedImage) {
		let url = baseURL.appendingPathComponent("/v1/image/\(image.id)/comments")
		let comments = CommentsUIComposer.commentsComposedWith(commentsLoader: makeRemoteCommentsLoader(url: url))
		navigationController.pushViewController(comments, animated: true)
	}

	private func makeRemoteCommentsLoader(url: URL) -> () -> ImageCommentsLoader.Publisher {
		let loader = RemoteLoader(
			url: url,
			client: httpClient,
			mapper: ImageCommentsMapper.map)
		return { return loader.loadPublisher() }
	}
	
	func configureWindow() {
		window?.rootViewController = navigationController
		window?.makeKeyAndVisible()
	}
	
	func sceneWillResignActive(_ scene: UIScene) {
		localFeedLoader.validateCache { _ in }
	}
	
	private func makeRemoteFeedLoaderWithLocalFallback() -> FeedLoader.Publisher {
		return remoteFeedLoader
			.loadPublisher()
			.caching(to: localFeedLoader)
			.fallback(to: localFeedLoader.loadPublisher)
	}
	
	private func makeLocalImageLoaderWithRemoteFallback(url: URL) -> FeedImageDataLoader.Publisher {
		return localImageLoader
			.loadImageDataPublisher(from: url)
			.fallback(to: { [remoteImageLoader, localImageLoader] in
				remoteImageLoader
					.loadImageDataPublisher(from: url)
					.caching(to: localImageLoader, using: url)
			})
	}
}

extension RemoteLoader: FeedLoader where Resource == [FeedImage] {}

extension RemoteLoader: ImageCommentsLoader where Resource == [ImageComment] {}

extension RemoteTaskLoader: FeedImageDataLoader where Resource == Data {}
