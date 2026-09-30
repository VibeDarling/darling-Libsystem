require 'tmpdir'
require 'open3'
root=ARGV.fetch(0,File.expand_path('..',__dir__))
source=File.read("#{root}/init.c")
names=%w[libSystem_atfork_child libSystem_posix_spawn_child]
bodies=names.map{|n|source[/#{n}\(void\)\s*\{.*?^\}/m] or abort "missing #{n}"}
callbacks=bodies.join.scan(/^\s*([A-Za-z_]\w*)\(\);/).flatten.uniq
special=%w[_malloc_fork_child __darling_arm64_thread_bridge_postfork_complete cc_atfork_child]
Dir.mktmpdir('libsystem-order-') do |dir|
  program=<<~C
    static int phase, completed;
    static void check(int ok) { if(!ok) __builtin_trap(); }
    static void _malloc_fork_child(void) { check(phase==0); phase=1; }
    static void __darling_arm64_thread_bridge_postfork_complete(void) {
      check(phase==1); phase=2; ++completed;
    }
    static void cc_atfork_child(void) { check(phase==1 || phase==2); phase=3; }
    #{(callbacks-special).map{|n|"static void #{n}(void) {}"}.join("\n")}
    #{bodies.map{|body|"void #{body}"}.join("\n")}
    int main(void) {
      #{names.map{|n|"phase=0; completed=0; #{n}(); check(phase==3 && completed==EXPECT_COMPLETION);"}.join("\n")}
      return 0;
    }
  C
  File.write("#{dir}/probe.c",program)
  # No system headers are used: select the actual production guard branches
  # independently of this test runner's host architecture.
  [['arm64',%w[-DDARLING -D__arm64__=1],1],
   ['aarch64',%w[-DDARLING -D__aarch64__=1],1],
   ['other-arch',%w[-DDARLING],0],['non-darling',[],0]].each do |name,flags,count|
    out,status=Open3.capture2e('clang','-U__arm64__','-U__aarch64__',*flags,"-DEXPECT_COMPLETION=#{count}",'-fsanitize=address,undefined',"#{dir}/probe.c",'-o',"#{dir}/probe")
    abort out unless status.success?
    out,status=Open3.capture2e("#{dir}/probe",rlimit_core:0)
    abort "FAIL #{name}: #{out}" unless status.success?
    puts "PASS fork/spawn completion ordering: #{name}"
  end
end
