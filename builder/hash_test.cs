using System;
using System.Text;
class HashTest {
 static int Main() {
  // CityHash64 1.0.3 vectors; Mozilla's published Firefox installation ID is
  // essential: shorter paths differ under later CityHash implementations.
  string[] inputs={"", "a", "hello", "Hello, World!", "The quick brown fox jumps over the lazy dog"};
  string[] hashes={"9AE16A3B2F90404F","2420662CD003ACFA","23C7ADA5F323C8DF","3D880BD14A5A7954","E7BA87D247C31277"};
  for(int i=0;i<inputs.Length;i++)
    if(InstallHash.CityHash64(Encoding.UTF8.GetBytes(inputs[i])).ToString("X16")!=hashes[i]) {
      Console.Error.WriteLine("CityHash mismatch for vector "+i);return 1;
    }
  string firefox=@"C:\Program Files\Mozilla Firefox";
  if(InstallHash.CityHash64(Encoding.Unicode.GetBytes(firefox)).ToString("X16")!="308046B0AF4A39CB") {
      Console.Error.WriteLine("Mozilla Firefox reference install hash differs");return 2;
  }
  Console.WriteLine("Mozilla CityHash64 vectors: PASS");return 0;
 }
}
