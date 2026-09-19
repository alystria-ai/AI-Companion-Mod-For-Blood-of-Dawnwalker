using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

// Installed only while composing. Routes real user keystrokes to our textbox
// without activating a second window or sending synthetic input to the game.
public sealed class ComposerKeys : IDisposable {
    delegate IntPtr Hook(int code,IntPtr message,IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct KeyData {public uint key,scan,flags,time;public IntPtr extra;}
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int type,Hook callback,IntPtr module,uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
    [DllImport("user32.dll")] static extern bool GetKeyboardState(byte[] state);
    [DllImport("user32.dll")] static extern IntPtr GetKeyboardLayout(uint thread);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int ToUnicodeEx(uint key,uint scan,byte[] state,StringBuilder text,int size,uint flags,IntPtr layout);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    // Windows can still enter a hook callback after UnhookWindowsHookEx returns.
    // One process-lifetime thunk avoids collecting the previous editor's delegate.
    static readonly Hook callback=Dispatch;
    static ComposerKeys current;
    readonly byte[] state=new byte[256];readonly Func<bool> eligible;bool disposed;
    readonly Action<Keys,string,bool,bool> deliver;readonly Control dispatcher;readonly bool repeat;IntPtr handle;
    public ComposerKeys(Control dispatcher,Func<bool> eligible,Action<Keys,string,bool,bool> deliver,bool repeat=true){
        if(current!=null)current.Dispose();
        this.dispatcher=dispatcher;this.eligible=eligible;this.deliver=deliver;this.repeat=repeat;GetKeyboardState(state);
        handle=SetWindowsHookEx(13,callback,GetModuleHandle(null),0);
        if(handle==IntPtr.Zero)throw new InvalidOperationException("Text input hook unavailable");
        current=this;
    }
    static IntPtr Dispatch(int code,IntPtr message,IntPtr data){
        var owner=current;
        try{if(owner!=null&&!owner.disposed)return owner.OnKey(code,message,data);}
        catch(Exception e){HostDiagnostics.Log("Keyboard callback",e);}
        return CallNextHookEx(IntPtr.Zero,code,message,data);
    }
    IntPtr OnKey(int code,IntPtr message,IntPtr data){
        if(code<0||!eligible())return CallNextHookEx(handle,code,message,data);
        var k=(KeyData)Marshal.PtrToStructure(data,typeof(KeyData));if(k.key>255)return CallNextHookEx(handle,code,message,data);
        bool down=message.ToInt32()==0x100||message.ToInt32()==0x104;
        bool wasDown=(state[k.key]&128)!=0;state[k.key]=(byte)((state[k.key]&1)|(down?128:0));
        if(k.key==20&&down&&!wasDown)state[20]^=1;
        state[16]=(byte)((state[160]|state[161])&128);state[17]=(byte)((state[162]|state[163])&128);state[18]=(byte)((state[164]|state[165])&128);
        // Let OS task switching work normally. No input is captured outside the game.
        if((state[18]&128)!=0||k.key==91||k.key==92)return CallNextHookEx(handle,code,message,data);
        if(down&&(repeat||!wasDown)){
            bool shift=(state[16]&128)!=0,ctrl=(state[17]&128)!=0;string text="";
            if(!ctrl&&k.key>=32){var buffer=new StringBuilder(16);int n=ToUnicodeEx(k.key,k.scan,state,buffer,16,4,GetKeyboardLayout(0));if(n>0)text=buffer.ToString(0,Math.Min(n,buffer.Length));}
            var key=(Keys)k.key;
            if(!dispatcher.IsDisposed&&dispatcher.IsHandleCreated)dispatcher.BeginInvoke(new Action(()=>{
                if(disposed||!Object.ReferenceEquals(current,this)||dispatcher.IsDisposed)return;
                try{if(eligible())deliver(key,text,shift,ctrl);}catch(Exception e){HostDiagnostics.Log("Composer input",e);}
            }));
        }
        return new IntPtr(1);
    }
    public void Dispose(){disposed=true;if(Object.ReferenceEquals(current,this))current=null;if(handle!=IntPtr.Zero){UnhookWindowsHookEx(handle);handle=IntPtr.Zero;}GC.KeepAlive(callback);}
}
