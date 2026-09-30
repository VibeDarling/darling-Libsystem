require 'tmpdir'
source=File.read(File.expand_path('../init.c',__dir__))
cleanup=source[/static void\nlibSystem_atfork_parent_cleanup\(int fork_succeeded\)\n\{.*?\n\}/m] or abort 'cleanup missing'
parent=source[/void\nlibSystem_atfork_parent\(void\)\n\{.*?\n\}/m] or abort 'parent missing'
failed=source[/static void\nlibSystem_atfork_failed\(void\)\n\{.*?\n\}/m] or abort 'failure missing'
names=%w[_pthread_atfork_parent _malloc_fork_parent cc_atfork_parent _dyld_atfork_parent dispatch_atfork_parent xpc_atfork_parent _libSC_info_fork_parent _mach_fork_parent _pthread_atfork_parent_handlers]
Dir.mktmpdir('fork-cleanup-') do |dir|
  code="#include <assert.h>\n#include <stdio.h>\n#define DARLING 1\n#define TARGET_OS_DRIVERKIT 0\nstatic int events[20],count;\n"
  names.each_with_index { |name,i| code+="static void #{name}(void) { events[count++]=#{i}; }\n" }
  code += [cleanup,parent,failed].join("\n")
  code += <<~C
    int main(void) {
      libSystem_atfork_parent(); assert(count==9);
      for(int i=0;i<9;++i) assert(events[i]==i);
      count=0; libSystem_atfork_failed(); assert(count==8);
      for(int i=0;i<7;++i) assert(events[i]==i);
      assert(events[7]==8);
      puts("PASS failed fork skips only Mach child wait; all parent cleanup/client handlers retained");
    }
  C
  File.write("#{dir}/test.c",code)
  system('clang','-Wall','-Wextra','-fsanitize=address,undefined',"#{dir}/test.c",'-o',"#{dir}/test",exception:true)
  system("#{dir}/test",exception:true)
end
