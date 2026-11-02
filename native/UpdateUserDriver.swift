#if canImport(Sparkle)
import AppKit
import Sparkle

struct LabUpdateButton {
    let id: String
    let title: String
}
struct LabUpdatePresentation {
    let stage: String
    let title: String
    let message: String
    var notes: String = ""
    var progress: Double? = nil
    var busy: Bool = false
    var buttons: [LabUpdateButton] = []
}

private final class LabUpdatePanel: NSPanel {
    var cancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { cancel?() }
}

// SPUUserDriver is Sparkle's public UI boundary. The standard driver provides
// deprecated compatibility methods; every current visible callback is owned
// here, so framework or OS locale never chooses this app's update copy.
final class LabUpdateUserDriver: SPUStandardUserDriver, NSWindowDelegate {
    let isEnglish: () -> Bool
    let presentationSink: ((LabUpdatePresentation) -> Void)?
    let presentsWindows: Bool
    var dismissalSink: (() -> Void)?
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
    private(set) var presentation: LabUpdatePresentation?
    private var renderCurrent: (() -> LabUpdatePresentation)?
    private var actions: [String: () -> Void] = [:]
    private var repeatableActions=Set<String>()
    private var closeAction: String?
    private(set) var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var messageLabel: NSTextField?
    private var notesView: NSTextView?
    private var notesScroll: NSScrollView?
    private var progressView: NSProgressIndicator?
    private var buttonStack: NSStackView?
    private var bodyHeight: NSLayoutConstraint?
    private var titleHeight: NSLayoutConstraint?
    private var messageHeight: NSLayoutConstraint?
    private var notesHeight: NSLayoutConstraint?
    private var actionsHeight: NSLayoutConstraint?
    private var received: UInt64 = 0
    private var expected: UInt64 = 0
    private var extraction: Double = 0
    private var currentItem: SUAppcastItem?
    private var downloadedNotes: String?

    init(hostBundle: Bundle, isEnglish: @escaping () -> Bool, presentationSink: ((LabUpdatePresentation) -> Void)? = nil, presentsWindows: Bool = true) {
        self.isEnglish=isEnglish;self.presentationSink=presentationSink;self.presentsWindows=presentsWindows
        super.init(hostBundle:hostBundle,delegate:nil)
    }
    private func copy(_ zh: String, _ en: String) -> String { isEnglish() ? en : zh }
    private func button(_ id: String, _ zh: String, _ en: String) -> LabUpdateButton { LabUpdateButton(id:id,title:copy(zh,en)) }
    private func show(close: String? = nil, actions: [String: () -> Void] = [:], repeatable: Set<String> = [], _ build: @escaping () -> LabUpdatePresentation) {
        closeAction=close;self.actions=actions;repeatableActions=repeatable;renderCurrent=build;refreshLanguage()
    }
    func refreshLanguage() {
        guard let value=renderCurrent?() else{return}
        presentation=value
        if let sink=presentationSink {sink(value)} else {render(value)}
    }
    func performAction(_ id: String) {
        guard let action=actions[id] else{return}
        // Sparkle's choice replies are one-shot. Retrying app termination is
        // explicitly repeatable in SPUUserDriver's public contract.
        if repeatableActions.contains(id) {action();return}
        actions.removeAll();closeAction=nil
        buttonStack?.arrangedSubviews.forEach{($0 as? NSButton)?.isEnabled=false}
        action()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id=closeAction {performAction(id)}
        return false
    }
    @objc private func clicked(_ sender: NSButton) {performAction(sender.identifier?.rawValue ?? "")}
    private func render(_ value: LabUpdatePresentation) {
        let wasVisible=panel?.isVisible == true
        if panel == nil {
            let window=LabUpdatePanel(contentRect:NSRect(x:0,y:0,width:480,height:196),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.delegate=self
            window.cancel={ [weak self] in if let id=self?.closeAction {self?.performAction(id)} }
            let content=NSView();window.contentView=content
            let title=NSTextField(wrappingLabelWithString:"");title.font = .boldSystemFont(ofSize:19)
            let message=NSTextField(wrappingLabelWithString:"");message.font = .systemFont(ofSize:13);message.textColor = .secondaryLabelColor
            title.identifier=NSUserInterfaceItemIdentifier("lab-update-title")
            message.identifier=NSUserInterfaceItemIdentifier("lab-update-message")
            let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
            scroll.identifier=NSUserInterfaceItemIdentifier("lab-update-notes")
            let notes=NSTextView();notes.isEditable=false;notes.isSelectable=true;notes.drawsBackground=false;notes.font = .systemFont(ofSize:13)
            notes.frame=NSRect(x:0,y:0,width:512,height:210)
            notes.textContainerInset=NSSize(width:4,height:8);notes.autoresizingMask=[.width];notes.isVerticallyResizable=true;notes.isHorizontallyResizable=false
            notes.textContainer?.widthTracksTextView=true;scroll.documentView=notes
            let progress=NSProgressIndicator();progress.style = .bar
            let buttons=NSStackView();buttons.orientation = .horizontal;buttons.spacing=10;buttons.alignment = .centerY;buttons.distribution = .fill
            buttons.identifier=NSUserInterfaceItemIdentifier("lab-update-actions")
            let stack=NSStackView(views:[title,message,scroll,progress]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=16;stack.detachesHiddenViews=true;stack.distribution = .fill
            for view in [stack,title,message,scroll,progress,buttons] {view.translatesAutoresizingMaskIntoConstraints=false}
            content.addSubview(stack);content.addSubview(buttons)
            titleHeight=title.heightAnchor.constraint(equalToConstant:26)
            messageHeight=message.heightAnchor.constraint(equalToConstant:20)
            notesHeight=scroll.heightAnchor.constraint(equalToConstant:160)
            bodyHeight=stack.heightAnchor.constraint(equalToConstant:62)
            actionsHeight=buttons.heightAnchor.constraint(equalToConstant:28)
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:22),title.widthAnchor.constraint(equalTo:stack.widthAnchor),message.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),progress.widthAnchor.constraint(equalTo:stack.widthAnchor),progress.heightAnchor.constraint(equalToConstant:6),buttons.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),buttons.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),buttons.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-22),titleHeight!,messageHeight!,notesHeight!,bodyHeight!,actionsHeight!])
            titleLabel=title;messageLabel=message;notesView=notes;notesScroll=scroll;progressView=progress;buttonStack=buttons;panel=window
        }
        let width:CGFloat=value.notes.isEmpty ? 480 : 560
        let textWidth=width-48
        let paragraph=NSMutableParagraphStyle();paragraph.lineSpacing=3
        let titleFont=NSFont.boldSystemFont(ofSize:19),messageFont=NSFont.systemFont(ofSize:13)
        func textHeight(_ text:String,font:NSFont,width:CGFloat,paragraph:NSParagraphStyle?=nil)->CGFloat {
            var attributes:[NSAttributedString.Key:Any]=[.font:font]
            if let paragraph=paragraph {attributes[.paragraphStyle]=paragraph}
            return ceil((text as NSString).boundingRect(with:NSSize(width:width,height:100000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes).height)+4
        }
        panel?.title=copy("NuPhy Lab 软件更新","NuPhy Lab Software Update")
        titleLabel?.preferredMaxLayoutWidth=textWidth;messageLabel?.preferredMaxLayoutWidth=textWidth
        titleLabel?.stringValue=value.title
        messageLabel?.attributedStringValue=NSAttributedString(string:value.message,attributes:[.font:messageFont,.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph])
        let headingHeight=textHeight(value.title,font:titleFont,width:textWidth)
        let detailHeight=textHeight(value.message,font:messageFont,width:textWidth,paragraph:paragraph)
        titleHeight?.constant=headingHeight;messageHeight?.constant=detailHeight
        notesView?.string=value.notes;notesScroll?.isHidden=value.notes.isEmpty
        let releaseNotesHeight=min(240,max(120,textHeight(value.notes,font:messageFont,width:textWidth-24)+16))
        notesHeight?.constant=releaseNotesHeight
        notesView?.frame.size=NSSize(width:textWidth,height:max(releaseNotesHeight,textHeight(value.notes,font:messageFont,width:textWidth-24)+16))
        progressView?.isHidden = !value.busy && value.progress == nil
        progressView?.isIndeterminate=value.progress == nil
        if let progress=value.progress {progressView?.stopAnimation(nil);progressView?.doubleValue=max(0,min(1,progress))*100}
        else if value.busy {progressView?.startAnimation(nil)} else {progressView?.stopAnimation(nil)}
        if let buttons=buttonStack {
            for child in buttons.arrangedSubviews {buttons.removeArrangedSubview(child);child.removeFromSuperview()}
            let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
            buttons.addArrangedSubview(spacer)
            for item in value.buttons.reversed() {
                let button=NSButton(title:item.title,target:self,action:#selector(clicked));button.bezelStyle = .rounded;button.identifier=NSUserInterfaceItemIdentifier(item.id)
                button.isEnabled=actions[item.id] != nil
                button.setContentHuggingPriority(.required,for:.horizontal);button.setContentCompressionResistancePriority(.required,for:.horizontal)
                if ["install","ok","allow","info"].contains(item.id) {button.keyEquivalent="\r"}
                else if item.id == closeAction {button.keyEquivalent="\u{1b}"}
                buttons.addArrangedSubview(button)
            }
            buttons.isHidden=value.buttons.isEmpty
        }
        let hasProgress=value.busy || value.progress != nil
        let contentHeight=headingHeight+detailHeight+16+(value.notes.isEmpty ? 0 : releaseNotesHeight+16)+(hasProgress ? 22 : 0)
        bodyHeight?.constant=contentHeight
        let footerHeight:CGFloat=value.buttons.isEmpty ? 0 : 28
        actionsHeight?.constant=footerHeight
        let height=max(196,22+contentHeight+(value.buttons.isEmpty ? 0 : 24+footerHeight)+22)
        if let panel=panel {
            let previous=panel.frame
            panel.setContentSize(NSSize(width:width,height:height))
            panel.contentView?.layoutSubtreeIfNeeded()
            if wasVisible {panel.setFrameOrigin(NSPoint(x:previous.midX-panel.frame.width/2,y:previous.maxY-panel.frame.height))}
            else if presentsWindows {panel.center()}
        }
        panel?.standardWindowButton(.closeButton)?.isEnabled=closeAction != nil
        if presentsWindows && !wasVisible {panel?.makeKeyAndOrderFront(nil)}
    }
    private func notes(for item: SUAppcastItem) -> String {
        if let text=localizedAppReleaseNotes(downloadedNotes ?? item.itemDescription ?? "",version:item.versionString,english:isEnglish()) {return text}
        return copy("此版本尚未提供可显示的中文更新说明。","Release notes in English are not available for this version.")
    }
    private func errorMessage(_ error: Error) -> String {
        let value=error as NSError
        // NSError.localizedDescription can use the OS language. Explain the
        // failure from stable codes instead of displaying foreign-language UI.
        let message: String
        if value.domain == NSURLErrorDomain || [1000,1002,2001].contains(value.code) {
            message=copy("无法获取更新，请检查网络后重试。","Could not fetch the update. Check your connection and try again.")
        } else if [3001,3002,4009].contains(value.code) {
            message=copy("更新验证未通过，当前软件不会被替换。请稍后重试。","The update could not be verified. Your current app will not be replaced. Try again later.")
        } else if [4001,4012].contains(value.code) {
            message=copy("尚无权限安装更新。请确认此应用的安装权限后重试。","Permission to install the update was not granted. Check this app's installation permissions and try again.")
        } else {
            message=copy("未能完成更新。当前软件、作品和设置均保留，请稍后重试。","The update could not finish. Your current app, artwork and settings are kept. Try again later.")
        }
        return message+copy(" 错误代码："," Error code: ")+String(value.code)
    }
    override func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        show(close:"later",actions:["allow":{reply(SUUpdatePermissionResponse(automaticUpdateChecks:true,automaticUpdateDownloading:false,sendSystemProfile:false))},"later":{reply(SUUpdatePermissionResponse(automaticUpdateChecks:false,automaticUpdateDownloading:false,sendSystemProfile:false))}]) { [unowned self] in
            LabUpdatePresentation(stage:"permission",title:copy("自动检查软件更新？","Check for updates automatically?"),message:copy("有新版本时会显示版本号和更新说明。下载安装前始终询问，不发送系统资料。","New versions show their version number and release notes. You choose when to download and install. No system profile is sent."),buttons:[button("allow","允许自动检查","Allow Checks"),button("later","稍后","Later")])
        }
    }
    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        show(close:"cancel",actions:["cancel":cancellation]) { [unowned self] in
            LabUpdatePresentation(stage:"checking",title:copy("正在检查更新…","Checking for updates…"),message:copy("正在获取最新软件版本。","Looking for the latest app version."),busy:true,buttons:[button("cancel","取消","Cancel")])
        }
    }
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        showFound(appcastItem,stage:state.stage,reply:reply)
    }
    // Kept separately so offline tests can exercise the real user-driver UI
    // without manufacturing Sparkle's non-public update-state initializer.
    func showFound(_ item: SUAppcastItem, stage: SPUUserUpdateStage = .notDownloaded, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        currentItem=item;downloadedNotes=nil
        var handlers:[String:()->Void]=["later":{reply(.dismiss)},"skip":{reply(.skip)}]
        if item.isInformationOnlyUpdate {
            handlers["info"]={ [weak self] in if let url=item.infoURL,url.scheme == "https" {self?.openURL(url)};reply(.dismiss)}
        } else {handlers["install"]={reply(.install)}}
        show(close:"later",actions:handlers) { [unowned self] in
            let message=stage == .installing ? copy("更新已准备安装。选择稍后会保留待安装更新；退出 NuPhy Lab 时可能自动安装。","The update is ready to install. Later keeps it ready; it may install when NuPhy Lab quits.") : copy("查看此版本的更新说明，然后选择是否更新。","Review this version's release notes and choose when to update.")
            return LabUpdatePresentation(stage:"found",title:copy("NuPhy Lab \(item.displayVersionString) 可用","NuPhy Lab \(item.displayVersionString) is available"),message:message,notes:notes(for:item),buttons:[item.isInformationOnlyUpdate ? button("info","查看详情","More Info") : stage == .installing ? button("install","安装并重新打开","Install and Relaunch") : button("install","更新","Update"),button("later","稍后","Later"),button("skip","跳过此版本","Skip This Version")])
        }
    }
    override func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        downloadedNotes=String(data:downloadData.data,encoding:.utf8);refreshLanguage()
    }
    override func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {downloadedNotes="";refreshLanguage()}
    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        show(close:"ok",actions:["ok":acknowledgement]) { [unowned self] in
            let reason=((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
            let message=reason == 3 ? copy("此更新需要更新版本的 macOS。","This update requires a newer version of macOS.") : reason == 4 ? copy("此更新尚不支持当前 macOS 版本。","This update does not support this macOS version yet.") : reason == 5 ? copy("此更新适用于 Apple Silicon Mac。","This update requires an Apple Silicon Mac.") : copy("当前没有适用于这台 Mac 的更新版本。","No newer update is available for this Mac.")
            return LabUpdatePresentation(stage:"notFound",title:copy("暂无可用更新","No Update Available"),message:message,buttons:[button("ok","完成","Done")])
        }
    }
    override func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        show(close:"ok",actions:["ok":acknowledgement]) { [unowned self] in
            LabUpdatePresentation(stage:"error",title:copy("更新暂时无法完成","Unable to Update"),message:errorMessage(error),buttons:[button("ok","知道了","OK")])
        }
    }
    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received=0;expected=0
        show(close:"cancel",actions:["cancel":cancellation]) { [unowned self] in
            LabUpdatePresentation(stage:"downloading",title:copy("正在下载更新…","Downloading Update…"),message:copy("下载完成后会验证安装包，再询问安装。","The download will be verified before you choose to install."),progress:expected > 0 ? Double(received)/Double(expected) : nil,busy:true,buttons:[button("cancel","取消","Cancel")])
        }
    }
    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {expected=expectedContentLength;refreshLanguage()}
    override func showDownloadDidReceiveData(ofLength length: UInt64) {received=received.addingReportingOverflow(length).partialValue;refreshLanguage()}
    override func showDownloadDidStartExtractingUpdate() {
        extraction=0
        show { [unowned self] in
            LabUpdatePresentation(stage:"extracting",title:copy("正在准备更新…","Preparing Update…"),message:copy("正在解包并验证更新，请稍候。","Extracting and verifying the update. Please wait."),progress:extraction,busy:true)
        }
    }
    override func showExtractionReceivedProgress(_ progress: Double) {extraction=max(0,min(1,progress));refreshLanguage()}
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        show(close:"later",actions:["install":{reply(.install)},"later":{reply(.dismiss)}]) { [unowned self] in
            LabUpdatePresentation(stage:"ready",title:copy("更新已准备就绪","Ready to Install"),message:copy("安装并重新打开 NuPhy Lab，作品与设置会保留。选择稍后会保留待安装更新；退出软件时可能自动安装。","Install and reopen NuPhy Lab. Your artwork and settings are kept. Later keeps the update ready; it may install when the app quits."),buttons:[button("install","安装并重新打开","Install and Relaunch"),button("later","稍后","Later")])
        }
    }
    override func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        show(actions:applicationTerminated ? [:] : ["retry":retryTerminatingApplication],repeatable:applicationTerminated ? [] : ["retry"]) { [unowned self] in
            LabUpdatePresentation(stage:"installing",title:copy("正在安装更新…","Installing Update…"),message:applicationTerminated ? copy("安装完成后会重新打开软件。","The app will reopen after installation.") : copy("正在等待 NuPhy Lab 安全退出。如仍未继续，可再次尝试。","Waiting for NuPhy Lab to quit safely. Try again if installation does not continue."),busy:true,buttons:applicationTerminated ? [] : [button("retry","重试退出","Try Again")])
        }
    }
    override func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        show(close:"ok",actions:["ok":acknowledgement]) { [unowned self] in
            LabUpdatePresentation(stage:"installed",title:copy("更新已安装","Update Installed"),message:relaunched ? copy("NuPhy Lab 已重新打开。","NuPhy Lab has reopened.") : copy("下次打开 NuPhy Lab 时即可使用新版本。","The new version is ready the next time you open NuPhy Lab."),buttons:[button("ok","完成","Done")])
        }
    }
    override func dismissUpdateInstallation() {
        actions.removeAll();repeatableActions.removeAll();renderCurrent=nil;presentation=nil;closeAction=nil;currentItem=nil;downloadedNotes=nil
        progressView?.stopAnimation(nil);panel?.orderOut(nil);dismissalSink?()
    }
    override func showUpdateInFocus() {if presentsWindows {panel?.makeKeyAndOrderFront(nil)}}
}
#endif
