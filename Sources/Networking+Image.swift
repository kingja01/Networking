import Foundation
import UIKit

public extension Networking {
    #if os(iOS) || os(tvOS) || os(watchOS)
    /**
     Downloads an image using the specified path.
     - parameter path: The path where the image is located
     - parameter cacheName: The cache name used to identify the downloaded image, by default the path is used.
     - parameter completion: A closure that gets called when the image download request is completed, it contains an `UIImage` object and a `NSError`.
     */
    public func downloadImage(path: String, cacheName: String? = nil, completion: (image: UIImage?, error: NSError?) -> ()) {
        let destinationURL: NSURL
        if let cacheName = cacheName {
            let replacedPath = cacheName.stringByReplacingOccurrencesOfString("/", withString: "-")
            guard let url = NSURL(string: replacedPath) else { fatalError("Couldn't create a destination url using cacheName: \(replacedPath)") }
            guard let cachesURL = NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).first else { fatalError("Couldn't normalize url") }
            destinationURL = cachesURL.URLByAppendingPathComponent(url.absoluteString)
        } else {
            destinationURL = self.destinationURL(path)
        }
        self.downloadImage(requestURL: self.urlForPath(path), destinationURL: destinationURL, path: path, completion: completion)
    }

    func downloadImage(requestURL requestURL: NSURL, destinationURL: NSURL, path: String, completion: (image: UIImage?, error: NSError?) -> ()) {
        if let getFakeRequests = self.fakeRequests[.GET], fakeRequest = getFakeRequests[path] {
            if fakeRequest.statusCode.statusCodeType() == .Successful, let image = fakeRequest.response as? UIImage {
                completion(image: image, error: nil)
            } else {
                let error = NSError(domain: Networking.ErrorDomain, code: fakeRequest.statusCode, userInfo: [NSLocalizedDescriptionKey : NSHTTPURLResponse.localizedStringForStatusCode(fakeRequest.statusCode)])
                completion(image: nil, error: error)
            }
        } else if let image = self.imageCache.objectForKey(destinationURL.absoluteString) as? UIImage {
            completion(image: image, error: nil)
        } else if NSFileManager.defaultManager().fileExistsAtURL(destinationURL) {
            if TestCheck.isTesting {
                guard let data = NSFileManager.defaultManager().contentsAtPath(destinationURL.path!) else { fatalError("Couldn't get image in destination url: \(destinationURL)") }
                guard let image = UIImage(data: data) else { fatalError("Couldn't get convert image using data: \(data)") }
                self.imageCache.setObject(image, forKey: destinationURL.absoluteString)
                completion(image: image, error: nil)
            } else {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {
                    guard let data = NSData(contentsOfURL: destinationURL) else { fatalError("Couldn't get image in destination url: \(destinationURL)") }
                    guard let image = UIImage(data: data) else { fatalError("Couldn't get convert image using data: \(data)") }
                    dispatch_async(dispatch_get_main_queue(), {
                        self.imageCache.setObject(image, forKey: destinationURL.absoluteString)
                        completion(image: image, error: nil)
                    })
                })
            }
        } else {
            let request = NSMutableURLRequest(URL: requestURL)
            request.HTTPMethod = RequestType.GET.rawValue
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = dispatch_semaphore_create(0)
            var returnedData: NSData?
            var returnedImage: UIImage?
            var returnedError: NSError?
            var returnedResponse: NSURLResponse?

            NetworkActivityIndicator.sharedIndicator.visible = true

            self.session.downloadTaskWithRequest(request, completionHandler: { url, response, error in
                returnedResponse = response
                returnedError = error

                if returnedError == nil, let url = url, data = NSData(contentsOfURL: url), image = UIImage(data: data) {
                    returnedData = data
                    returnedImage = image

                    data.writeToURL(destinationURL, atomically: true)
                    self.imageCache.setObject(image, forKey: destinationURL.absoluteString)
                } else if let url = url {
                    if let response = response as? NSHTTPURLResponse {
                        returnedError = NSError(domain: Networking.ErrorDomain, code: response.statusCode, userInfo: [NSLocalizedDescriptionKey : NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode)])
                    } else {
                        returnedError = NSError(domain: Networking.ErrorDomain, code: 500, userInfo: [NSLocalizedDescriptionKey : "Failed to load url: \(url.absoluteString)"])
                    }
                }

                if TestCheck.isTesting && self.disableTestingMode == false {
                    dispatch_semaphore_signal(semaphore)
                } else {
                    dispatch_async(dispatch_get_main_queue(), {
                        NetworkActivityIndicator.sharedIndicator.visible = false

                        self.logError(.JSON, parameters: nil, data: returnedData, request: request, response: response, error: returnedError)
                        completion(image: returnedImage, error: returnedError)
                    })
                }
            }).resume()

            if TestCheck.isTesting && self.disableTestingMode == false {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)

                self.logError(.JSON, parameters: nil, data: returnedData, request: request, response: returnedResponse, error: returnedError)
                completion(image: returnedImage, error: returnedError)
            }
        }
    }

    /**
     Cancels the image download request for the specified path. This causes the request to complete with error code -999
     - parameter path: The path for the cancelled image download request
     */
    public func cancelImageDownload(path: String) {
        let url = self.urlForPath(path)
        self.cancelRequest(.Download, requestType: .GET, url: url)
    }

    /**
     Registers a fake download image request with an UIImage. After registering this, every download request to the path, will return
     the registered UIImage.
     - parameter path: The path for the faked image download request.
     - parameter image: A UIImage that will be returned when there's a request to the registered path
     */
    public func fakeImageDownload(path: String, image: UIImage?, statusCode: Int = 200) {
        self.fake(.GET, path: path, response: image, statusCode: statusCode)
    }
    #endif
}