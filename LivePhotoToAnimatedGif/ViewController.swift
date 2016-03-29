//
//  ViewController.swift
//  LivePhotoToAnimatedGif
//
//  Created by itok on 2016/03/18.
//  Copyright © 2016年 sorakae Inc. All rights reserved.
//

import UIKit
import Photos
import PhotosUI
import ImageIO
import MobileCoreServices

class ViewController: UIViewController {

	@IBOutlet weak var livePhotoView: PHLivePhotoView!
	@IBOutlet weak var webView: UIWebView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.
		self.checkAuthorization()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	func checkAuthorization() {
		PHPhotoLibrary.requestAuthorization { (status) -> Void in
			if status == .Authorized {
				self.searchLivePhoto()
			}
		}
	}

	func searchLivePhoto() {
		// I want to search the live photos with predicate, but cannot make predicate with OptionSetType in Swift.
		/*
		let opts = PHFetchOptions()
		opts.predicate = NSPredicate(format: "mediaSubtypes.rawValue & %d != 0", PHAssetMediaSubtype.PhotoLive.rawValue)
		let result = PHAsset.fetchAssetsWithMediaType(.Image, options: opts)
		*/
		
		// get all images
		let result = PHAsset.fetchAssetsWithMediaType(.Image, options: nil)
		var photoAsset: PHAsset?
		result.enumerateObjectsWithOptions(.Reverse, usingBlock: { (obj, idx, stop) -> Void in
			let asset = obj as! PHAsset
			// search the latest live photo
			if asset.mediaSubtypes.contains(.PhotoLive) {
				photoAsset = asset
				stop.memory = true
			}
		})
		
		// get live photo data
		if let photoAsset = photoAsset {
			PHImageManager.defaultManager().requestLivePhotoForAsset(photoAsset, targetSize: CGSizeZero, contentMode: .Default, options: nil) { (livePhoto, info) -> Void in
				if let livePhoto = livePhoto {
					self.livePhotoView.livePhoto = livePhoto
				}
			}
		}
	}
	
	@IBAction func convert(sender: AnyObject) {
		guard let livePhoto = self.livePhotoView.livePhoto else {
			return
		}
		
		// search movie in live photo
		let resources = PHAssetResource.assetResourcesForLivePhoto(livePhoto)
		for resource in resources {
			if resource.type == .PairedVideo {
				self.getMovieData(resource)
				break
			}
		}
	}
	
	func getMovieData(resource: PHAssetResource) {
		let moviePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent(resource.originalFilename)
		let movieURL = NSURL(fileURLWithPath: moviePath)
		let movieData = NSMutableData()

		// load movie data
		PHAssetResourceManager.defaultManager().requestDataForAssetResource(resource, options: nil, dataReceivedHandler: { (data) -> Void in
			movieData.appendData(data)
		}) { (err) -> Void in
			do {
				try movieData.writeToURL(movieURL, options: NSDataWritingOptions.AtomicWrite)
				let movieAsset = AVAsset(URL: movieURL)
				self.convertToGif(movieAsset, resource: resource)
			} catch {
				
			}
		}
	}
	
	func convertToGif(movieAsset: AVAsset, resource: PHAssetResource) {
		// gif frames
		let numFrame = 30
		let frameValue = movieAsset.duration.value / Int64(numFrame)
		let timeScale = movieAsset.duration.timescale
		var times = Array<NSValue>()
		for i in 0..<numFrame {
			let time = CMTimeMakeWithEpoch(frameValue * Int64(i), timeScale, movieAsset.duration.epoch)
			times.append(NSValue(CMTime: time))
		}
		
		guard let docDir = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first else {
			return
		}
		let gifPath = (docDir as NSString).stringByAppendingPathComponent((resource.originalFilename as NSString).stringByDeletingPathExtension + ".gif")
		let gifURL = NSURL(fileURLWithPath: gifPath)

		guard let gif = CGImageDestinationCreateWithURL(gifURL, kUTTypeGIF, numFrame, nil) else {
			return
		}
		
		let delay = CMTimeGetSeconds(movieAsset.duration) / Float64(numFrame)
		let frameProperty = [String(kCGImagePropertyGIFDictionary): [String(kCGImagePropertyGIFDelayTime): delay]]
		
		var cnt = 0
		// generate thumbnails and write to gif
		let generator = AVAssetImageGenerator(asset: movieAsset)
		// generate in any timelines
		generator.requestedTimeToleranceBefore = kCMTimeZero
		generator.requestedTimeToleranceAfter = kCMTimeZero
		// apply video transform
		generator.appliesPreferredTrackTransform = true
		generator.maximumSize = CGSizeMake(640, 640)
		generator.generateCGImagesAsynchronouslyForTimes(times) { (requested, image, actual, result, err) -> Void in
			if let image = image {
				CGImageDestinationAddImage(gif, image, frameProperty)
			}
			cnt += 1
			if cnt >= numFrame {
				let gifProperty = [String(kCGImagePropertyGIFDictionary): [String(kCGImagePropertyGIFLoopCount): 0]]
				CGImageDestinationSetProperties(gif, gifProperty)
				CGImageDestinationFinalize(gif)
				
				dispatch_async(dispatch_get_main_queue(), { () -> Void in
					self.webView.loadRequest(NSURLRequest(URL: gifURL))
				})
			}
		}
	}
}

