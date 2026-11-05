// Prepare the public Accessibility interface before a physical command arrives.
// This bridge never edits keybindings, posts a key, or presses an AX control.
export class CodexAccessibilityBridge {
  constructor({prepare,enabled=()=>true}) {
    this.prepare=prepare;this.enabled=enabled;
    this.current={status:'idle',message:'',actions:{},activationConfirmed:false};
  }
  snapshot(){return structuredClone(this.current);}
  async close(){this.closed=true;await this.pending;}
  resume(){this.closed=false;}
  async inspect(){
    if(this.pending)return this.pending;
    if(this.closed||!this.enabled()) {
      this.current={status:'idle',message:'',actions:{},activationConfirmed:false};
      return this.snapshot();
    }
    this.pending=Promise.resolve().then(()=>this.prepare()).then(result=>{
      if(this.closed||!this.enabled())return this.snapshot();
      // Prepared describes opt-in only, never a successful command or approval.
      const status=['prepared','warming','permission-required','open-app','ambiguous'].includes(result?.status)?result.status:'unavailable';
      this.current={status,message:status==='permission-required'?'请允许辅助功能，授权后会自动连接。':status==='open-app'?'请打开 Codex。':status==='ambiguous'?'请保留一个 Codex 应用实例。':'',
        delivery:'accessibility',actions:{},activationConfirmed:false};
      return this.snapshot();
    }).catch(()=>{
      if(!this.closed)this.current={status:'unavailable',message:'',actions:{},activationConfirmed:false};
      return this.snapshot();
    }).finally(()=>{this.pending=null;});
    return this.pending;
  }
}
