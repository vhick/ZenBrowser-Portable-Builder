using System;
using System.Text;
class HashTest {
 static int Main() {
  string[] inputs={"", "a", "hello", "Hello, World!", "The quick brown fox jumps over the lazy dog"};
  string[] hashes={"9AE16A3B2F90404F","B3454265B6DF75E3","B48BE5A931380CE8","9DA0E1CBFAEA2842","C268724928FECA7D"};
  for(int i=0;i<inputs.Length;i++) if(InstallHash.CityHash64(Encoding.UTF8.GetBytes(inputs[i])).ToString("X16")!=hashes[i]) {
    Console.Error.WriteLine("CityHash mismatch for vector "+i);return 1;
  }
  Console.WriteLine("Mozilla install-hash CityHash64 vectors: PASS");return 0;
 }
}
