// Portable Zen Windows installation ID: CityHash64(UTF-16LE install directory).
// Based on Google CityHash (MIT license): https://github.com/google/cityhash
// Copyright (c) 2011 Google, Inc.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
using System;
using System.IO;
using System.Text;
using Microsoft.Win32;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

internal static class InstallHash
{
    const ulong K0=0xc3a5c85c97cb3127UL, K1=0xb492b66fbe98f273UL, K2=0x9ae16a3b2f90404fUL;
    const ulong KMul=0x9ddfea08eb382d69UL;
    static ulong F64(byte[] s,int o) { return BitConverter.ToUInt64(s,o); }
    static ulong F32(byte[] s,int o) { return BitConverter.ToUInt32(s,o); }
    static ulong R(ulong v,int n) { return n==0?v:(v>>n)|(v<<(64-n)); }
    static ulong M(ulong v) { return v^(v>>47); }
    static ulong H(ulong u,ulong v,ulong mul=KMul) { unchecked { ulong a=(u^v)*mul; a^=a>>47; ulong b=(v^a)*mul; b^=b>>47; return b*mul; } }
    static ulong Swap(ulong x) {
      return ((x&0x00000000000000ffUL)<<56)|((x&0x000000000000ff00UL)<<40)|
             ((x&0x0000000000ff0000UL)<<24)|((x&0x00000000ff000000UL)<<8)|
             ((x&0x000000ff00000000UL)>>8)|((x&0x0000ff0000000000UL)>>24)|
             ((x&0x00ff000000000000UL)>>40)|((x&0xff00000000000000UL)>>56);
    }
    static void Weak(byte[] s,int o,ulong aa,ulong bb,out ulong v0,out ulong v1) {
       unchecked { ulong w=F64(s,o),x=F64(s,o+8),y=F64(s,o+16),z=F64(s,o+24);
       aa+=w; bb=R(bb+aa+z,21); ulong c=aa; aa+=x+y; bb+=R(aa,44); v0=aa+z; v1=bb+c; }
    }
    internal static ulong CityHash64(byte[] s) {
      unchecked {
       int n=s.Length;
       // Mozilla's installation-hash implementation uses the v1.0.3 CityHash64
       // short-input formulas. Google's current CityHash v1.1+ produces DIFFERENT
       // hashes for <= 64 bytes, so it must not be used for installation IDs.
       if(n<=16) {
         if(n>8) { ulong a=F64(s,0),b=F64(s,n-8);
           return H(a,R(b+(ulong)n,n))^b; }
         if(n>=4) return H((ulong)n+(F32(s,0)<<3),F32(s,n-4));
         if(n>0) { ulong y=(ulong)s[0]+((ulong)s[n/2]<<8),z=(ulong)n+((ulong)s[n-1]<<2);
           return M(y*K2 ^ z*0xc949d7c7509e6557UL)*K2; }
         return K2;
       }
       if(n<=32) { ulong a=F64(s,0)*K1,b=F64(s,8),c=F64(s,n-8)*K2,d=F64(s,n-16)*K0;
         return H(R(a-b,43)+R(c,30)+d,a+R(b^0xc949d7c7509e6557UL,20)-c+(ulong)n); }
       if(n<=64) {
         ulong z=F64(s,24),a=F64(s,0)+((ulong)n+F64(s,n-16))*K0;
         ulong b=R(a+z,52),c=R(a,37);
         a+=F64(s,8);c+=R(a,7);a+=F64(s,16);
         ulong vf=a+z,vs=b+R(a,31)+c;
         a=F64(s,16)+F64(s,n-32);z=F64(s,n-8);b=R(a+z,52);c=R(a,37);
         a+=F64(s,n-24);c+=R(a,7);a+=F64(s,n-16);
         ulong wf=a+z,ws=b+R(a,31)+c;
         ulong r=M((vf+ws)*K2+(wf+vs)*K0);
         return M(r*K0+vs)*K2;
       }
       ulong X=F64(s,n-40),Y=F64(s,n-16)+F64(s,n-56),Z=H(F64(s,n-48)+(ulong)n,F64(s,n-24));
       ulong v0,v1,w0,w1; Weak(s,n-64,(ulong)n,Z,out v0,out v1); Weak(s,n-32,Y+K1,X,out w0,out w1); X=X*K1+F64(s,0);
       int off=0,len=(n-1)&~63;
       do { X=R(X+Y+v0+F64(s,off+8),37)*K1;
            Y=R(Y+v1+F64(s,off+48),42)*K1; X^=w1; Y+=v0+F64(s,off+40);
            Z=R(Z+w0,33)*K1; ulong a,b,c,d;
            Weak(s,off,v1*K1,X+w0,out a,out b); Weak(s,off+32,Z+w1,Y+F64(s,off+16),out c,out d);
            v0=a;v1=b;w0=c;w1=d; ulong swap=Z;Z=X;X=swap;off+=64;len-=64;
       } while(len!=0);
       return H(H(v0,w0)+M(Y)*K1+Z,H(v1,w1)+X);
      }
    }
    // Resolve the actual case and linked-directory target as Mozilla does
    // before hashing on Windows. Never trust guessed hashes for file deletion.
    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern SafeFileHandle CreateDirectoryHandle(string filename,
        uint access, FileShare share, IntPtr security, uint creation, uint flags,
        IntPtr template);
    [DllImport("kernel32.dll", EntryPoint="GetFinalPathNameByHandleW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern uint GetFinalPathName(SafeFileHandle handle,
        StringBuilder result, uint size, uint flags);

    internal static string RealDirectory(string path) {
        string original = Path.GetFullPath(path).TrimEnd('\\');
        try {
            using(SafeFileHandle handle=CreateDirectoryHandle(original, 0,
                    FileShare.ReadWrite|FileShare.Delete, IntPtr.Zero, 3,
                    FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
                if(handle==null || handle.IsInvalid) return original;
                StringBuilder result=new StringBuilder(32768);
                uint written=GetFinalPathName(handle,result,(uint)result.Capacity,0);
                if(written==0 || written>=result.Capacity) return original;
                string real=result.ToString();
                if(real.StartsWith(@"\\?\UNC\",StringComparison.OrdinalIgnoreCase))
                    real=@"\\"+real.Substring(8);
                else if(real.StartsWith(@"\\?\",StringComparison.OrdinalIgnoreCase))
                    real=real.Substring(4);
                if(!Path.IsPathRooted(real)) return original;
                return Path.GetFullPath(real).TrimEnd('\\');
            }
        } catch { return original; }
    }

    internal static string ForDirectory(string path) {
       string dir=RealDirectory(path);
       // Same priority as Mozilla's Windows code: machine cache before user.
       // Inspect both views because the registry's 32/64-bit view can differ.
       foreach(RegistryHive hive in new RegistryHive[] {
            RegistryHive.LocalMachine,RegistryHive.CurrentUser }) {
          foreach(RegistryView view in new RegistryView[] {
                RegistryView.Registry64,RegistryView.Registry32 }) {
             try {
               using(RegistryKey baseKey=RegistryKey.OpenBaseKey(hive,view))
               using(RegistryKey ids=baseKey.OpenSubKey(@"SOFTWARE\Mozilla\Zen\TaskBarIDs",false)) {
                 if(ids==null) continue;
                 foreach(string key in ids.GetValueNames()) {
                    if(!string.Equals(key,dir,StringComparison.OrdinalIgnoreCase)) continue;
                    if(ids.GetValueKind(key)!=RegistryValueKind.String) continue;
                    string val=ids.GetValue(key) as string;
                    if(!string.IsNullOrEmpty(val) &&
                       System.Text.RegularExpressions.Regex.IsMatch(val,@"\A[0-9a-fA-F]{1,16}\z"))
                       return val.ToUpperInvariant();
                 }
               }
             } catch { /* Never broaden deletion after an inaccessible key. */ }
          }
       }
       return CityHash64(Encoding.Unicode.GetBytes(dir)).ToString("X16");
    }
}
