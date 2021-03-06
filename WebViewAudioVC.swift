//
//  ViewController.swift
//  WebView Audio comunication
//
//  Created by Dahye on 2019/12/02.
//  Copyright © 2019 Dahye. All rights reserved.
//

import UIKit
import WebKit
import Alamofire
import AVFoundation
import SnapKit

/* 메인 화면 클래스 */
class MainVC: UIViewController, WKUIDelegate, WKNavigationDelegate, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    var webView = WKWebView()
    
    var audioSession = AVAudioSession()
    var audioRecorder: AVAudioRecorder?
    var audioPlayer = AVAudioPlayer()
    var isAudioRecordingGranted: Bool = false
    
    var isPlaying = false // 재생 중 인지?
    var isRecording = false // 레코딩 진행 중 인지?
    var checkRecording = false// 레코딩 가능한지?
    
    var idString = String()
    var isPreLogin = false
    var isAutoLogin = false
    
    override func loadView() {
        super.loadView()
        
        // Youtube inline
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
            
        webView.scrollView.bounces = false
        webView.backgroundColor = .black
        
        self.view.addSubview(webView)
        
        webView.uiDelegate = self
        webView.navigationDelegate = self
        
        // MARK: Snapkit Development
        if #available(iOS 11.0, *) {
            webView.snp.makeConstraints { (make) -> Void in
                make.height.equalTo(self.view.safeAreaLayoutGuide.snp.height)
                make.width.equalTo(self.view.safeAreaLayoutGuide.snp.width)
                make.leading.equalTo(self.view.safeAreaLayoutGuide.snp.leading)
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
            }
        } else {
            webView.snp.makeConstraints { (make) -> Void in
                make.height.equalToSuperview()
                make.width.equalToSuperview()
                make.leading.equalToSuperview()
                make.top.equalToSuperview()
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        load(urlString: Constants.BASEURL)
        checkRecordPermission()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.receivedNotification(notification:)), name: Notification.Name("NotificationIdentifier"), object: nil)
    }
    
    /* 푸시 수신 처리 */
    @objc func receivedNotification(notification: Notification) {
        if let targetUrl: String = PushInfo.sharedInstance.getTargetUrl() {
            load(urlString: targetUrl)
            PushInfo.sharedInstance.setTargetUrl(urlString: nil)
        }
    }
    
    /* 권한 체크, 오디오 녹음 권한 */
    func checkRecordPermission() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case AVAudioSessionRecordPermission.granted:
            isAudioRecordingGranted = true
            break
        case AVAudioSessionRecordPermission.denied:
            isAudioRecordingGranted = false
            break
        case AVAudioSessionRecordPermission.undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission({ (allowed) in
                if allowed {
                    self.isAudioRecordingGranted = true
                } else {
                    self.isAudioRecordingGranted = false
                }
            })
            break
        default:
            break
        }
    }
    
     /* 웹뷰 파일 쿠키 저장 */
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let response = navigationResponse.response as? HTTPURLResponse,
            let url = navigationResponse.response.url else {
                decisionHandler(.cancel)
                return
        }
        
        if let headerFields = response.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            cookies.forEach { cookie in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
        }
        
        decisionHandler(.allow)
    }
    
     /* 웹뷰 PHP Session 처리 */
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let absoluteString = navigationAction.request.url?.absoluteString ?? ""
        
        if let temp = UserDefaults.standard.value(forKey: "PHPSESSID") as? String {
            let cookieString : String = "document.cookie='PHPSESSID=\(temp);path=/;'"
            webView.evaluateJavaScript(cookieString)
        }
        
        decisionHandler(.allow)
    }
    
    
    /* 웹뷰 로드 처리, 디바이스 토큰 / 앱 버전 처리 */
    func load(urlString : String) {
        let appVersionString = DeviceInfo.getBuildVersion()
        var urlString = urlString + "?appver="+appVersionString
        
        if let deviceTokenString: String = UserDefaults.standard.string(forKey: Constants.FIREBASE_TOKEN) {
            urlString = urlString + "&Token=" + deviceTokenString
        }
        
        guard let urlInstance = URL(string: urlString) else {
            return
        }
        
        print("webView Load urlString :" + urlString)
        
        let request = URLRequest(url:urlInstance)
        webView.load(request)
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertContoller = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "취소", style: .cancel) {
            _ in completionHandler(false)
        }
        
        let okAction = UIAlertAction(title: "확인", style: .default) {
            _ in completionHandler(true)
        }
        
        alertContoller.addAction(cancelAction)
        alertContoller.addAction(okAction)
        
        DispatchQueue.main.async {
            self.present(alertContoller, animated: true, completion: nil)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let loadedSessid = UserDefaults.standard.value(forKey: "PHPSESSID") as! String?
        if let temp = loadedSessid {
            let cookieString : String = "document.cookie='PHPSESSID=\(temp);path=/;'"
            webView.evaluateJavaScript(cookieString)
        }
    }
    
    
    /* 웹뷰 javaScript Message 분기처리 */
    @available(iOS 8.0, *)
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        
        let arr = message.components(separatedBy: "::::")
        print(arr)
        
        if arr.count > 2 {
            idString = arr[2]
        }
        
        if message.contains("MICRECORD") {
            // 녹음 중지
            startRecording(message: message)
            completionHandler()
        } else if message.contains("RECORDPLAY") {
            // 파일 재생 진행
            playRecording()
            completionHandler()
        } else  {
            //  세션 처리(자동 로그인)
            if (message.contains("Welcome")) {
                    WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                        (cookies) in for cookie in cookies{
                            if cookie.name == "PHPSESSID" {
                                UserDefaults.standard.set(cookie.value, forKey:"PHPSESSID")
                            }
                        }
                    }
                    completionHandler()
            } else {
                let alertContoller = UIAlertController(title: message, message: nil, preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "확인", style: .cancel) {
                    _ in completionHandler()
                }
                alertContoller.addAction(cancelAction)
                DispatchQueue.main.async {
                    self.present(alertContoller, animated: true, completion: nil)
                }
            }
        }
    }
    
    
    
    // 오디오 파일 전송 부
    func sendAudioFile() {
        let apiUrl: URL = URL(string: "http://address.co.kr/app/php/upload.php?filepath="+idString+"&sampling=8000")!
        let voiceData = (try? Data(contentsOf: getFileUrl()))!
        print(voiceData.debugDescription )
        
        let param = [
            "Connection": "Keep-Alive",
            "ENCTYPE": "multipart/form-data",
            "Cache-Control": "no-cahce",
            "Content-Type": "multipart/form-data;boundary=*****",//application/json, multipart/form-data
        ]
        
        //
        Alamofire.upload(
            multipartFormData: {multipartFormData in
                for (key, value) in param {
                    multipartFormData.append(value.data(using: String.Encoding.utf8)!, withName: key)
                }
                multipartFormData.append(self.getFileUrl(), withName: "uploaded_file", fileName: "record.pcm", mimeType: "audio/pcm")
        },
            to: apiUrl,
            encodingCompletion: { encodingResult in
                switch encodingResult {
                case .success(let upload, _, _):
                    upload.responseJSON { response in
                        print("success")
                        debugPrint(response)
                    }
                case .failure(let encodingError):
                    debugPrint(encodingError)
                }
        }
        )
        
    }
    
    // Get Document File
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory
    }
    
    // Get File Url
    func getFileUrl() -> URL {
        let filename = "record.pcm"
        let filePath = getDocumentsDirectory().appendingPathComponent(filename)
        return filePath
    }
    
    // 오디오 최초 설정 및 파일 생성
    func setupAudioRecorder () {
        audioRecorder = AVAudioRecorder()
        if isAudioRecordingGranted {
            audioSession = AVAudioSession.sharedInstance()
            
            do {
                try audioSession.setCategory(.playAndRecord)
                try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.none)
                try audioSession.setActive(true)
                
                let settings = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 8000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVEncoderAudioQualityKey:AVAudioQuality.high.rawValue
                ]
                audioRecorder = try AVAudioRecorder(url: getFileUrl(), settings: settings)
                
                if audioRecorder != nil {
                    audioRecorder?.delegate = self
                    audioRecorder?.isMeteringEnabled = true
                    audioRecorder?.prepareToRecord()
                } else {
                    return
                }
            } catch {
                // failed to record!
                displayAlert(msg_title: "Error", msg_desc: error.localizedDescription, action_title: "OK")
            }
        } else {
            displayAlert(msg_title: "Error", msg_desc: "Don't have access to use your microphone.", action_title: "OK")
        }
    }
    
    // 녹음 시작 / 중지
    func startRecording(message: String) {
        if (message.contains("STOP")) {
            // 녹음 중지 명령
            if(isRecording) {
                finishAudioRecording(success: true)
                isRecording = false
                sendAudioFile()
            } else {
                // 녹음 중지 명령이지만 녹음중이 아니라면, 아무것도 하지 않음.
                print("서버 전송 중....")
            }
        } else {
           // 녹음 시작 명령
            setupAudioRecorder()
            audioRecorder?.record()
            isRecording = true
        }
    }
    
    // 녹음 종료
    public func finishAudioRecording(success: Bool) {
        if success {
            audioRecorder?.stop()
            audioRecorder = nil
            print("recorded successfully.")
        } else {
            displayAlert(msg_title: "Error", msg_desc: "Recording failed.", action_title: "OK")
        }
    }
    
    // 녹음 진행 준비
    func preparePlay() {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: getFileUrl())
            audioPlayer.delegate = self
            
            do {
                try audioSession.setCategory(.playback)
                try audioSession.overrideOutputAudioPort(AVAudioSession.PortOverride.speaker)
                try audioSession.setActive(true)
                
            } catch {
                // failed to Play!
//                displayAlert(msg_title: "Error", msg_desc: error.localizedDescription, action_title: "OK")
                print(error.localizedDescription)
            }
            
            audioPlayer.prepareToPlay()
            
            if audioSession.isHeadphonesConnected {
                print("isHeadphonesConnected")
                try audioSession.overrideOutputAudioPort(.none)
            } else {
                try audioSession.overrideOutputAudioPort(.speaker)
            }
        } catch{
            print("Error")
        }
    }
    
    // 녹음 재생
    func playRecording() {
        if(isPlaying) {
            audioPlayer.stop()
            isPlaying = false
        } else {
            if FileManager.default.fileExists(atPath: getFileUrl().path) {
                preparePlay()
                
                
                audioPlayer.play()
                isPlaying = true
            } else {
                print("Audio file is missing.")
            }
        }
    }
    
    // 녹음 종료시 서버 전송
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            finishAudioRecording(success: false)
        }
    }
    
    // 재생 종료시 플래그 수정
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            isPlaying = false
        }
    }
    
    // Alert
    func displayAlert(msg_title : String , msg_desc : String ,action_title : String)
    {
        let ac = UIAlertController(title: msg_title, message: msg_desc, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: action_title, style: .default)
        {
            (result : UIAlertAction) -> Void in
            _ = self.navigationController?.popViewController(animated: true)
        })
        present(ac, animated: true)
    }
}

// 오디오 세션 확장, 녹음 진행 및 재생시 이어폰 관련
extension AVAudioSession {
    static var isHeadphonesConnected: Bool {
        return sharedInstance().isHeadphonesConnected
    }

    var isHeadphonesConnected: Bool {
        return !currentRoute.outputs.filter { $0.isHeadphones }.isEmpty
    }
}

extension AVAudioSessionPortDescription {
    var isHeadphones: Bool {
        return portType == AVAudioSession.Port.headphones
    }
}
