if CommandLine.arguments.contains("--update-ui-qa") {
    precondition(Locale.preferredLanguages.first?.hasPrefix("zh") == true)
    var appEnglish=true
    var shown=[LabUpdatePresentation]()
    let driver=LabUpdateUserDriver(hostBundle:Bundle.main,isEnglish:{appEnglish},presentationSink:{shown.append($0)})
    let item=SUAppcastItem(dictionary:["sparkle:version":"2.0.0","sparkle:shortVersionString":"2.0.0","description":notes,"enclosure":["url":"https://example.invalid/NuPhyLab-2.0.0.dmg","length":"100","sparkle:edSignature":"fixture"]])!
    func assertEnglish() {
        guard let ui=driver.presentation else{preconditionFailure("Missing presentation")}
        let visible=[ui.title,ui.message,ui.notes]+ui.buttons.map{$0.title}
        precondition(visible.allSatisfy{!$0.unicodeScalars.contains{(0x3400...0x9fff).contains($0.value)}})
    }
    let callbacks=["showUpdatePermissionRequest:reply:","showUserInitiatedUpdateCheckWithCancellation:","showUpdateFoundWithAppcastItem:state:reply:","showUpdateReleaseNotesWithDownloadData:","showUpdateReleaseNotesFailedToDownloadWithError:","showUpdateNotFoundWithError:acknowledgement:","showUpdaterError:acknowledgement:","showDownloadInitiatedWithCancellation:","showDownloadDidReceiveExpectedContentLength:","showDownloadDidReceiveDataOfLength:","showDownloadDidStartExtractingUpdate","showExtractionReceivedProgress:","showReadyToInstallAndRelaunch:","showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:","showUpdateInstalledAndRelaunched:acknowledgement:","dismissUpdateInstallation","showUpdateInFocus"]
    for name in callbacks {precondition(LabUpdateUserDriver.instancesRespond(to:NSSelectorFromString(name)))}
    var choices=[SPUUserUpdateChoice]()
    driver.showFound(item){choices.append($0)}
    assertEnglish();precondition(driver.presentation?.title.contains("2.0.0") == true)
    precondition(driver.presentation?.notes == "Release notes")
    precondition(driver.presentation?.buttons.map{$0.title} == ["Update","Later","Skip This Version"])
    driver.performAction("later");driver.performAction("install");precondition(choices == [.dismiss])
    driver.showFound(item){choices.append($0)};driver.performAction("install");precondition(choices == [.dismiss,.install])
    driver.showFound(item){choices.append($0)};driver.performAction("skip");precondition(choices == [.dismiss,.install,.skip])
    driver.showFound(item){choices.append($0)}
    appEnglish=false;driver.refreshLanguage();precondition(driver.presentation?.notes == "版本说明")
    precondition(driver.presentation?.buttons.map{$0.title} == ["更新","稍后","跳过此版本"])
    appEnglish=true;driver.refreshLanguage();assertEnglish()
    var permission:SUUpdatePermissionResponse?
    driver.show(SPUUpdatePermissionRequest(systemProfile:[])){permission=$0};assertEnglish();driver.performAction("allow")
    precondition(permission?.automaticUpdateChecks == true && permission?.sendSystemProfile == false && permission?.automaticUpdateDownloading?.boolValue == false)
    driver.show(SPUUpdatePermissionRequest(systemProfile:[])){permission=$0};assertEnglish();driver.performAction("later");precondition(permission?.automaticUpdateChecks == false)
    var cancellations=0,acknowledgements=0,retries=0
    driver.showUserInitiatedUpdateCheck{cancellations+=1};assertEnglish();driver.performAction("cancel");driver.performAction("cancel");precondition(cancellations == 1)
    driver.showDownloadInitiated{cancellations+=1};assertEnglish();driver.showDownloadDidReceiveExpectedContentLength(100);driver.showDownloadDidReceiveData(ofLength:25);assertEnglish();precondition(driver.presentation?.progress == 0.25)
    driver.performAction("cancel");precondition(cancellations == 2)
    driver.showDownloadDidStartExtractingUpdate();assertEnglish();driver.showExtractionReceivedProgress(0.5);assertEnglish();precondition(driver.presentation?.progress == 0.5 && driver.presentation?.buttons.isEmpty == true)
    driver.showReady(toInstallAndRelaunch:{choices.append($0)});assertEnglish();driver.performAction("install");precondition(choices.last == .install)
    driver.showReady(toInstallAndRelaunch:{choices.append($0)});assertEnglish();driver.performAction("later");precondition(choices.last == .dismiss)
    driver.showInstallingUpdate(withApplicationTerminated:false,retryTerminatingApplication:{retries+=1});assertEnglish();driver.performAction("retry");driver.performAction("retry");precondition(retries == 2)
    driver.showInstallingUpdate(withApplicationTerminated:true,retryTerminatingApplication:{retries+=1});assertEnglish();precondition(driver.presentation?.buttons.isEmpty == true)
    for relaunched in [false,true] {driver.showUpdateInstalledAndRelaunched(relaunched,acknowledgement:{acknowledgements+=1});assertEnglish();driver.performAction("ok")}
    for reason in [0,1,2,3,4,5] {
        let error=NSError(domain:"SUSparkleErrorDomain",code:1001,userInfo:[NSLocalizedDescriptionKey:"您已经是最新版本。",SPUNoUpdateFoundReasonKey:NSNumber(value:reason)])
        driver.showUpdateNotFoundWithError(error,acknowledgement:{acknowledgements+=1});assertEnglish();driver.performAction("ok")
    }
    for code in [2001,3001,4001,9999] {
        let error=NSError(domain:"SUSparkleErrorDomain",code:code,userInfo:[NSLocalizedDescriptionKey:"系统中文错误：无法完成更新。"])
        driver.showUpdaterError(error,acknowledgement:{acknowledgements+=1});assertEnglish();precondition(driver.presentation?.message.contains(String(code)) == true);driver.performAction("ok")
    }
    precondition(acknowledgements == 12)
    driver.showFound(item){choices.append($0)}
    driver.showUpdateReleaseNotesFailedToDownloadWithError(NSError(domain:"NSURLErrorDomain",code:-1009,userInfo:[NSLocalizedDescriptionKey:"未连接互联网"]))
    assertEnglish();precondition(driver.presentation?.notes == "Release notes in English are not available for this version.")
    driver.showUpdateInFocus()
    driver.dismissUpdateInstallation();precondition(driver.presentation == nil)
    driver.performAction("install");precondition(choices.count == 5)
    // Inspect actual AppKit views without presenting a window or alert. This
    // catches default OS-localized buttons that a pure copy model could miss.
    NSApplication.shared.setActivationPolicy(.prohibited)
    func visibleStrings(_ view: NSView) -> [String] {
        let own: [String]
        if let label=view as? NSTextField {own=[label.stringValue]}
        else if let text=view as? NSTextView {own=[text.string]}
        else if let button=view as? NSButton {own=[button.title]}
        else {own=[]}
        return own+view.subviews.flatMap{visibleStrings($0)}
    }
    func checkNoChinese(_ strings: [String]) {precondition(strings.allSatisfy{!$0.unicodeScalars.contains{(0x3400...0x9fff).contains($0.value)}})}
    for kind in [AppUpdateAlertKind.preparationFailed,.keyboardReleaseFailed] {
        let alert=makeAppUpdateAlert(kind,english:true)
        checkNoChinese([alert.messageText,alert.informativeText]+alert.buttons.map{$0.title})
        precondition(alert.buttons.map{$0.title} == (kind == .preparationFailed ? ["OK"] : ["Try Again","Later"]))
        precondition(!alert.window.isVisible)
    }
    let offscreen=LabUpdateUserDriver(hostBundle:Bundle.main,isEnglish:{appEnglish},presentsWindows:false)
    var nativeChoices=[SPUUserUpdateChoice](),nativeCancellations=0
    offscreen.showFound(item){nativeChoices.append($0)}
    let updatePanel=offscreen.panel!
    precondition(!updatePanel.isVisible && updatePanel.title == "NuPhy Lab Software Update")
    checkNoChinese(visibleStrings(updatePanel.contentView!))
    let nativeButtons=updatePanel.contentView!.subviews.flatMap{visibleStrings($0)}
    precondition(nativeButtons.contains("Update") && nativeButtons.contains("Later") && nativeButtons.contains("Skip This Version") && nativeButtons.contains("Release notes"))
    precondition(!offscreen.windowShouldClose(updatePanel));precondition(!offscreen.windowShouldClose(updatePanel));precondition(nativeChoices == [.dismiss])
    offscreen.refreshLanguage()
    func buttons(_ view:NSView)->[NSButton] {(view as? NSButton).map{[$0]} ?? view.subviews.flatMap{buttons($0)}}
    precondition(buttons(updatePanel.contentView!).allSatisfy{!$0.isEnabled})
    offscreen.showUserInitiatedUpdateCheck{nativeCancellations+=1}
    precondition(!offscreen.windowShouldClose(updatePanel));precondition(!offscreen.windowShouldClose(updatePanel));precondition(nativeCancellations == 1)
    offscreen.showDownloadInitiated{nativeCancellations+=1}
    precondition(!offscreen.windowShouldClose(updatePanel));precondition(!offscreen.windowShouldClose(updatePanel));precondition(nativeCancellations == 2)
    offscreen.showDownloadDidStartExtractingUpdate()
    precondition(updatePanel.standardWindowButton(.closeButton)?.isEnabled == false)
    precondition(!offscreen.windowShouldClose(updatePanel));precondition(nativeCancellations == 2)
    offscreen.showReady(toInstallAndRelaunch:{nativeChoices.append($0)})
    checkNoChinese(visibleStrings(updatePanel.contentView!))
    precondition(!offscreen.windowShouldClose(updatePanel));precondition(!offscreen.windowShouldClose(updatePanel));precondition(nativeChoices == [.dismiss,.dismiss])
    offscreen.showUpdaterError(NSError(domain:"SUSparkleErrorDomain",code:3001,userInfo:[NSLocalizedDescriptionKey:"中文系统验证错误"]),acknowledgement:{})
    checkNoChinese(visibleStrings(updatePanel.contentView!))
    offscreen.showFound(item){nativeChoices.append($0)}
    appEnglish=false;offscreen.refreshLanguage();precondition(visibleStrings(updatePanel.contentView!).contains("更新"))
    appEnglish=true;offscreen.refreshLanguage();checkNoChinese(visibleStrings(updatePanel.contentView!))
    offscreen.dismissUpdateInstallation();precondition(!updatePanel.isVisible)
    precondition(NSApplication.shared.windows.allSatisfy{!$0.isVisible})
    print("{\"simulatedSystemChinese\":true,\"appEnglish\":true,\"presentations\":\(shown.count),\"GUIOpened\":false,\"network\":false,\"hardware\":false}")
}
