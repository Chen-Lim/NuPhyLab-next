import {useState} from 'react';
import {Button,run} from './primitives';
import {nativeCodexKeys} from './codexKeys';
import {OFFICIAL_DRIVER_URL,OfficialDriverAccess,useStartupCopy} from './StartupGuide';
import {availableFirmwareUpdate} from '../../shared/firmware-onboarding.mjs';
import type {AppState,Command} from './types';
import packageInfo from '../../package.json';
import './update-notices.css';

export function UpdatePreferences({state,command}:{state:AppState|null;command:Command}){
  const copy=useStartupCopy();
  const [checking,setChecking]=useState(false),[checkingFirmware,setCheckingFirmware]=useState(false),[error,setError]=useState('');
  const update=availableFirmwareUpdate(state),fw=state?.firmware;
  const identified=state?.device.connected===true||state?.device.identified===true&&state.device.firmwareDetectionAvailable===true;
  const firmwareMatches=fw?.modelId===state?.device.modelId&&fw?.current===state?.device.firmware&&fw?.stale!==true;
  const checkApp=async()=>{
    if(checking)return;setChecking(true);setError('');
    try{if(!await nativeCodexKeys({kind:'checkForUpdates'}))setError(copy('请在 NuPhy Lab 桌面应用中检查软件更新。','Check for software updates in the NuPhy Lab desktop app.'));}
    catch{setError(copy('暂时无法检查软件更新，请稍后重试。','Could not check for software updates. Try again shortly.'));}
    finally{setChecking(false);}
  };
  const checkFirmware=async()=>{
    if(checkingFirmware)return;setCheckingFirmware(true);setError('');
    try{await command({op:'checkFirmware'},{silent:true});}
    catch{setError(copy('暂时无法检查键盘固件，请稍后重试。','Could not check keyboard firmware. Try again shortly.'));}
    finally{setCheckingFirmware(false);}
  };
  const firmwareStatus=update?copy(`${update.model} 有新固件 ${update.target}，当前为 ${update.current}。`,`${update.model} firmware ${update.target} is available. Installed: ${update.current}.`)
    :!identified?copy('连接 USB 键盘后可检查适用于这把键盘的固件。','Connect your keyboard by USB to check firmware for this device.')
    :fw?.checking?copy('正在检查官方固件…','Checking official firmware…')
    :firmwareMatches&&fw?.latestConfirmed&&['current','newer'].includes(fw.status)?copy('当前键盘固件已是最新版本。','This keyboard firmware is up to date.')
    :copy('尚未确认这把键盘的最新固件，可手动重新检查。','The latest firmware for this keyboard is not confirmed. Check again manually.');
  return <div className="lab-update-preferences">
    <div className="lab-settings-intro"><h2>{copy('软件与固件更新','Software and firmware updates')}</h2><p>{copy('软件更新在 NuPhy Lab 中完成；键盘固件在官方 NuPhyIO 中更新。','Update the app in NuPhy Lab and keyboard firmware in the official NuPhyIO.')}</p></div>
    <section className="lab-setting-panel lab-update-panel" aria-label={copy('软件更新','Software updates')}>
      <div className="lab-setting-row"><div><h3>NuPhy Lab</h3><p>{copy('当前版本','Installed version')} {state?.build?.version||packageInfo.version}</p></div><Button busy={checking} onClick={()=>run(checkApp())}>{copy('检查软件更新','Check app updates')}</Button></div>
      <p>{copy('发现新版本时会显示版本号和该版更新说明，可选择更新或稍后。选择稍后后，同一版本 24 小时内不再自动提醒；手动检查仍可打开。选择跳过此版本后，只会自动提醒更新的版本。','New versions show their version number and release notes, with Update or Later. Later pauses automatic reminders for that version for 24 hours; manual checks remain available. Skip This Version silences that version until a newer one is available.')}</p>
    </section>
    <section className="lab-setting-panel lab-update-panel" aria-label={copy('键盘固件','Keyboard firmware')}>
      <div className="lab-setting-row"><div><h3>{copy('键盘固件','Keyboard firmware')}{update&&<span className="lab-firmware-update-label">{copy('有可用更新','Update available')}</span>}</h3><p role="status">{firmwareStatus}</p></div><Button disabled={!identified||fw?.checking} busy={checkingFirmware||fw?.checking} onClick={()=>run(checkFirmware())}>{copy('检查固件','Check firmware')}</Button></div>
      {update&&<><p>{copy('请在 NuPhyIO 中选择当前键盘并按官方提示更新，完成后关闭 NuPhyIO 再返回。','Select this keyboard in NuPhyIO and follow its update instructions. Close NuPhyIO before returning.')}</p><OfficialDriverAccess compact/><a className="lab-update-address" href={OFFICIAL_DRIVER_URL}>{OFFICIAL_DRIVER_URL}</a></>}
    </section>
    {error&&<p className="settings-v6-note is-error" role="alert">{error}</p>}
  </div>;
}
