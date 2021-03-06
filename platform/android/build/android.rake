#
require File.dirname(__FILE__) + '/androidcommon.rb'
require 'pathname'

USE_STLPORT = true
USE_TRACES = false

ANDROID_API_LEVEL_TO_MARKET_VERSION = {}
ANDROID_MARKET_VERSION_TO_API_LEVEL = {}
{2 => "1.1", 3 => "1.5", 4 => "1.6", 5 => "2.0", 6 => "2.0.1", 7 => "2.1", 8 => "2.2"}.each do |k,v|
  ANDROID_API_LEVEL_TO_MARKET_VERSION[k] = v
  ANDROID_MARKET_VERSION_TO_API_LEVEL[v] = k
end

def get_market_version(apilevel)
  ANDROID_API_LEVEL_TO_MARKET_VERSION[apilevel]
end

def get_api_level(version)
  ANDROID_MARKET_VERSION_TO_API_LEVEL[version]
end

JAVA_PACKAGE_NAME = 'com.rhomobile.rhodes'

# Here is place were android platform should be specified.
# For complete list of android API levels and its mapping to
# market names (such as "Android-1.5" etc) see output of
# command "android list targets"
ANDROID_API_LEVEL = 4

ANDROID_PERMISSIONS = {
  'audio' => ['RECORD_AUDIO', 'MODIFY_AUDIO_SETTINGS'],
  'camera' => 'CAMERA',
  'gps' => 'ACCESS_FINE_LOCATION',
  'network_state' => 'ACCESS_NETWORK_STATE',
  'phone' => ['CALL_PHONE', 'READ_PHONE_STATE'],
  'pim' => ['READ_CONTACTS', 'WRITE_CONTACTS', 'GET_ACCOUNTS'],
  'record_audio' => 'RECORD_AUDIO',
  'vibrate' => 'VIBRATE',
  'bluetooth' => ['BLUETOOTH_ADMIN', 'BLUETOOTH'],
  'calendar' => ['READ_CALENDAR', 'WRITE_CALENDAR'],
  'push' => proc do |manifest| add_push(manifest) end
}

def add_push(manifest)
  element = REXML::Element.new('permission')
  element.add_attribute('android:name', "#{$app_package_name}.permission.C2D_MESSAGE")
  element.add_attribute('android:protectionLevel', 'signature')
  manifest.add element

  element = REXML::Element.new('uses-permission')
  element.add_attribute('android:name', "#{$app_package_name}.permission.C2D_MESSAGE")
  manifest.add element

  element = REXML::Element.new('uses-permission')
  element.add_attribute('android:name', "com.google.android.c2dm.permission.RECEIVE")
  manifest.add element

  receiver = REXML::Element.new('receiver')
  receiver.add_attribute('android:name', "#{JAVA_PACKAGE_NAME}.PushReceiver")
  receiver.add_attribute('android:permission', "com.google.android.c2dm.permission.SEND")

  action = REXML::Element.new('action')
  action.add_attribute('android:name', "com.google.android.c2dm.intent.RECEIVE")
  category = REXML::Element.new('category')
  category.add_attribute('android:name', $app_package_name)

  ie = REXML::Element.new('intent-filter')
  ie.add_element(action)
  ie.add_element(category)
  receiver.add_element(ie)

  action = REXML::Element.new('action')
  action.add_attribute('android:name', "com.google.android.c2dm.intent.REGISTRATION")
  category = REXML::Element.new('category')
  category.add_attribute('android:name', $app_package_name)
  
  ie = REXML::Element.new('intent-filter')
  ie.add_element(action)
  ie.add_element(category)
  receiver.add_element(ie)

  manifest.elements.each('application') do |app|
    app.add receiver
  end
end

def set_app_name_android(newname)
  puts "set_app_name"
  $stdout.flush

  rm_rf $appres
  cp_r $rhores, $appres

  iconappname = File.join($app_path, "icon", "icon.png")
  iconresname = File.join($appres, "drawable", "icon.png")
  rm_f iconresname
  cp iconappname, iconresname

  rhostrings = File.join($rhores, "values", "strings.xml")
  appstrings = File.join($appres, "values", "strings.xml")
  doc = REXML::Document.new(File.new(rhostrings))
  doc.elements["resources/string[@name='app_name']"].text = newname
  File.open(appstrings, "w") { |f| doc.write f }

  version = {'major' => 0, 'minor' => 0, 'patch' => 0}
  if $app_config["version"]
    if $app_config["version"] =~ /^(\d+)$/
      version["major"] = $1.to_i
    elsif $app_config["version"] =~ /^(\d+)\.(\d+)$/
      version["major"] = $1.to_i
      version["minor"] = $2.to_i
    elsif $app_config["version"] =~ /^(\d+)\.(\d+)\.(\d+)$/
      version["major"] = $1.to_i
      version["minor"] = $2.to_i
      version["patch"] = $3.to_i
    end
  end
  
  version = version["major"]*10000 + version["minor"]*100 + version["patch"]

  doc = REXML::Document.new(File.new($rhomanifest))
  doc.root.attributes['package'] = $app_package_name
  if version > 0
    doc.root.attributes['android:versionCode'] = version.to_s
    doc.root.attributes['android:versionName'] = $app_config["version"]
  end

  doc.elements.delete "manifest/application/uses-library[@android:name='com.google.android.maps']" unless $use_geomapping

  caps_proc = []
  caps = ['INTERNET', 'PERSISTENT_ACTIVITY', 'WAKE_LOCK']
  $app_config["capabilities"].each do |cap|
    cap = ANDROID_PERMISSIONS[cap]
    next if cap.nil?
    if cap.is_a? Proc
      caps_proc << cap
      next
    end
    cap = [cap] if cap.is_a? String
    cap = [] unless cap.is_a? Array
    caps += cap
  end
  caps.uniq!

  manifest = doc.elements["manifest"]

  manifest.elements.each('uses-sdk') { |e| manifest.delete e }
  element = REXML::Element.new('uses-sdk')
  element.add_attribute('android:minSdkVersion', ANDROID_API_LEVEL.to_s)
  manifest.add element

  # Clear C2DM stuff
  doc.elements.delete "manifest/application/receiver[@android:name='com.rhomobile.rhodes.PushReceiver']"
  manifest.elements.each('permission') do |e|
    name = e.attribute('name', 'android')
    next if name.nil?
    manifest.delete(e) if name.to_s =~ /\.C2D_MESSAGE$/
  end

  manifest.elements.each('uses-permission') { |e| manifest.delete e }
  caps.sort.each do |cap|
    element = REXML::Element.new('uses-permission')
    element.add_attribute('android:name', "android.permission.#{cap}")
    manifest.add element
  end

  caps_proc.each do |p|
    p.call manifest
  end

  File.open($appmanifest, "w") { |f| doc.write f, 2 }

  buf = File.new($rho_android_r,"r").read.gsub(/^\s*import com\.rhomobile\..*\.R;\s*$/,"\nimport #{$app_package_name}.R;\n")
  File.open($app_android_r,"w") { |f| f.write(buf) }
end

def generate_rjava
  Rake::Task["build:android:rjava"].execute
end

def get_boolean(arg)
  arg == 'true' or arg == 'yes' or arg == 'enabled' or arg == 'enable' or arg == '1'
end

namespace "config" do
  task :set_android_platform do
    $current_platform = "android"
  end

  task :android => [:set_android_platform, "config:common"] do

    $gapikey = $app_config["android"]["apikey"] unless $app_config["android"].nil?
    $gapikey = $config["android"]["apikey"] if $gapikey.nil? and not $config["android"].nil?
    $gapikey = '' unless $gapikey.is_a? String
    $gapikey = nil if $gapikey.empty?

    $use_geomapping = $app_config["android"]["mapping"] unless $app_config["android"].nil?
    $use_geomapping = $config["android"]["mapping"] if $use_geomapping.nil? and not $config["android"].nil?
    $use_geomapping = 'false' if $use_geomapping.nil?
    $use_geomapping = get_boolean($use_geomapping.to_s)

    $use_google_addon_api = false
    $use_google_addon_api = true if $use_geomapping

    $emuversion = $app_config["android"]["version"] unless $app_config["android"].nil?
    $emuversion = $config["android"]["version"] if $emuversion.nil? and !$config["android"].nil?

    # Here is switch between release/debug configuration used for
    # building native libraries
    if $app_config["debug"].nil?
      $build_release = true
    else
      $build_release = !$app_config["debug"].to_i
    end

    $androidsdkpath = $config["env"]["paths"]["android"]
    unless File.exists? $androidsdkpath
      puts "Missing or invalid 'android' section in rhobuild.yml"
      exit 1
    end

    $androidndkpath = $config["env"]["paths"]["android-ndk"]
    unless File.exists? $androidndkpath
      puts "Missing or invalid 'android-ndk' section in rhobuild.yml"
      exit 1
    end

    errfmt = "WARNING!!! Path to Android %s contain spaces! It will not work because of the Google toolchain restrictions. Move it to another location and reconfigure rhodes."
    if $androidsdkpath =~ /\s/
      puts(errfmt % "SDK")
      exit 1
    end
    if $androidndkpath =~ /\s/
      puts(errfmt % "NDK")
      exit 1
    end

    $java = $config["env"]["paths"]["java"]
    $androidpath = Jake.get_absolute $config["build"]["androidpath"]
    $bindir = File.join($app_path, "bin")
    $rhobindir = File.join($androidpath, "bin")
    $builddir = File.join($androidpath, "build")
    $shareddir = File.join($androidpath, "..", "shared")
    $srcdir = File.join($bindir, "RhoBundle")
    $targetdir = File.join($bindir, "target")
    $excludelib = ['**/builtinME.rb','**/ServeME.rb','**/TestServe.rb']
    $tmpdir = File.join($bindir, "tmp")
    $resourcedir = File.join($tmpdir, "resource")
    $libs = File.join($androidpath, "Rhodes", "libs")
    $appname = $app_config["name"]
    $appname = "Rhodes" if $appname.nil?
    $app_package_name = "com.rhomobile." + $appname.downcase.gsub(/[^A-Za-z_0-9]/, '')

    $rhomanifest = File.join $androidpath, "Rhodes", "AndroidManifest.xml"
    $appmanifest = File.join $tmpdir, "AndroidManifest.xml"

    $rhores = File.join $androidpath, "Rhodes", "res"
    $appres = File.join $tmpdir, "res"

    $appincdir = File.join $tmpdir, "include"

    $rho_android_r = File.join $androidpath, "Rhodes", "src", "com", "rhomobile", "rhodes", "AndroidR.java"
    $app_android_r = File.join $tmpdir, "AndroidR.java"
    $app_rjava_dir = File.join $tmpdir
    $app_native_libs_java = File.join $tmpdir, "NativeLibraries.java"
    $app_capabilities_java = File.join $tmpdir, "Capabilities.java"
    $app_push_java = File.join $tmpdir, "Push.java"

    if RUBY_PLATFORM =~ /(win|w)32$/
      $emulator = #"cmd /c " + 
        File.join( $androidsdkpath, "tools", "emulator.exe" )
      $bat_ext = ".bat"
      $exe_ext = ".exe"
      $path_separator = ";"

      # Add PATH to cygwin1.dll
      ENV['CYGWIN'] = 'nodosfilewarning'
      if $path_cygwin_modified.nil?
        ENV['PATH'] = Jake.get_absolute("res/build-tools") + ";" + ENV['PATH']
        path_cygwin_modified = true
      end
    else
      #XXX make these absolute
      $emulator = File.join( $androidsdkpath, "tools", "emulator" )
      $bat_ext = ""
      $exe_ext = ""
      $path_separator = ":"
      # TODO: add ruby executable for Linux
    end

    puts "+++ Looking for platform..." if USE_TRACES
    napilevel = ANDROID_API_LEVEL
    Dir.glob(File.join($androidsdkpath, "platforms", "*")).each do |platform|
      props = File.join(platform, "source.properties")
      unless File.file? props
        puts "+++ WARNING! No source.properties found in #{platform}"
        next
      end

      apilevel = -1
      marketversion = nil
      File.open(props, "r") do |f|
        while line = f.gets
          apilevel = $1.to_i if line =~ /^\s*AndroidVersion\.ApiLevel\s*=\s*([0-9]+)\s*$/
          marketversion = $1 if line =~ /^\s*Platform\.Version\s*=\s*([^\s]*)\s*$/
        end
      end

      puts "+++ API LEVEL of #{platform}: #{apilevel}" if USE_TRACES

      if apilevel > napilevel
        napilevel = apilevel
        $androidplatform = File.basename(platform)
        $found_api_level = apilevel
      end
    end

    if $androidplatform.nil?
      ajar = File.join($androidsdkpath, 'platforms', 'android-' + ANDROID_API_LEVEL_TO_MARKET_VERSION[ANDROID_API_LEVEL], 'android.jar')
      $androidplatform = 'android-' + ANDROID_API_LEVEL_TO_MARKET_VERSION[ANDROID_API_LEVEL] if File.file?(ajar)
    end

    if $androidplatform.nil?
      puts "+++ No required platform (API level >= #{ANDROID_API_LEVEL}) found, can't proceed"
      exit 1
    else
      puts "+++ Platform found: #{$androidplatform}" if USE_TRACES
    end
    $stdout.flush
    
    $dx = File.join( $androidsdkpath, "platforms", $androidplatform, "tools", "dx" + $bat_ext )
    $aapt = File.join( $androidsdkpath, "platforms", $androidplatform, "tools", "aapt" + $exe_ext )
    $apkbuilder = File.join( $androidsdkpath, "tools", "apkbuilder" + $bat_ext )
    $androidbin = File.join( $androidsdkpath, "tools", "android" + $bat_ext )
    $adb = File.join( $androidsdkpath, "tools", "adb" + $exe_ext )
    $zipalign = File.join( $androidsdkpath, "tools", "zipalign" + $exe_ext )
    $androidjar = File.join($androidsdkpath, "platforms", $androidplatform, "android.jar")

    $keytool = File.join( $java, "keytool" + $exe_ext )
    $jarsigner = File.join( $java, "jarsigner" + $exe_ext )
    $jarbin = File.join( $java, "jar" + $exe_ext )

    $keystore = nil
    $keystore = $app_config["android"]["production"]["certificate"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $keystore = $config["android"]["production"]["certificate"] if $keystore.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $keystore = File.expand_path(File.join(ENV['HOME'], ".rhomobile", "keystore")) if $keystore.nil?

    $storepass = nil
    $storepass = $app_config["android"]["production"]["password"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $storepass = $config["android"]["production"]["password"] if $storepass.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $storepass = "81719ef3a881469d96debda3112854eb" if $storepass.nil?
    $keypass = $storepass

    $storealias = nil
    $storealias = $app_config["android"]["production"]["alias"] if !$app_config["android"].nil? and !$app_config["android"]["production"].nil?
    $storealias = $config["android"]["production"]["alias"] if $storealias.nil? and !$config["android"].nil? and !$config["android"]["production"].nil?
    $storealias = "rhomobile.keystore" if $storealias.nil?

    $app_config["capabilities"] = [] if $app_config["capabilities"].nil?
    $app_config["capabilities"] = [] unless $app_config["capabilities"].is_a? Array
    if $app_config["android"] and $app_config["android"]["capabilities"]
      $app_config["capabilities"] += $app_config["android"]["capabilities"]
      $app_config["android"]["capabilities"] = nil
    end
    $app_config["capabilities"].map! { |cap| cap.is_a?(String) ? cap : nil }.delete_if { |cap| cap.nil? }
    $use_google_addon_api = true unless $app_config["capabilities"].index("push").nil?

    # Detect android targets
    if $androidtargets.nil?
      $androidtargets = {}
      id = nil

      `"#{$androidbin}" list targets`.split(/\n/).each do |line|
        line.chomp!

        if line =~ /^id:\s+([0-9]+)/
          id = $1
        end

        if $use_google_addon_api
          if line =~ /:Google APIs:([0-9]+)/
            apilevel = $1
            $androidtargets[apilevel.to_i] = id.to_i
          end
        else
          if line =~ /^\s+API\s+level:\s+([0-9]+)$/ and not id.nil?
            apilevel = $1
            $androidtargets[apilevel.to_i] = id.to_i
          end
        end
      end
    end

    # Detect Google API add-on path
    if $use_google_addon_api
      puts "+++ Looking for Google APIs add-on..." if USE_TRACES
      napilevel = ANDROID_API_LEVEL
      Dir.glob(File.join($androidsdkpath, 'add-ons', '*')).each do |dir|

        props = File.join(dir, 'manifest.ini')
        if !File.file? props
          puts "+++ WARNING: no manifest.ini found in #{dir}"
          next
        end

        apilevel = -1
        File.open(props, 'r') do |f|
          while line = f.gets
            next unless line =~ /^api=([0-9]+)$/
            apilevel = $1.to_i
            break
          end
        end

        puts "+++ API LEVEL of #{dir}: #{apilevel}" if USE_TRACES

        if apilevel > napilevel
          napilevel = apilevel
          $gapijar = File.join(dir, 'libs', 'maps.jar')
          $found_api_level = apilevel
        end
      end
      if $gapijar.nil?
        puts "+++ No Google APIs add-on found (which is required because appropriate capabilities enabled in build.yml)"
        exit 1
      else
        puts "+++ Google APIs add-on found: #{$gapijar}" if USE_TRACES
      end
    end

    $emuversion = get_market_version($found_api_level) if $emuversion.nil?
    $emuversion = $emuversion.to_s
    $avdname = "rhoAndroid" + $emuversion.gsub(/[^0-9]/, "")
    $avdname += "ext" if $use_google_addon_api
    $avdtarget = $androidtargets[get_api_level($emuversion)]

    setup_ndk($androidndkpath, ANDROID_API_LEVEL)
    
    $stlport_includes = File.join $shareddir, "stlport", "stlport"

    $native_libs = ["sqlite", "curl", "stlport", "ruby", "json", "rhocommon", "rhodb", "rholog", "rhosync", "rhomain"]

    if $build_release
      $confdir = "release"
    else
      $confdir = "debug"
    end
    $objdir = {}
    $libname = {}
    $native_libs.each do |x|
      $objdir[x] = File.join($rhobindir, $confdir, $ndkgccver, "lib" + x)
      $libname[x] = File.join($rhobindir, $confdir, $ndkgccver, "lib" + x + ".a")
    end

    $extensionsdir = $bindir + "/libs/" + $confdir + "/" + $ndkgccver + "/extensions"

    #$app_config["extensions"] = [] if $app_config["extensions"].nil?
    #$app_config["extensions"] = [] unless $app_config["extensions"].is_a? Array
    #if $app_config["android"] and $app_config["android"]["extensions"]
    #  $app_config["extensions"] += $app_config["android"]["extensions"]
    #  $app_config["android"]["extensions"] = nil
    #end

    $push_sender = nil
    $push_sender = $config["android"]["push"]["sender"] if !$config["android"].nil? and !$config["android"]["push"].nil?
    $push_sender = $app_config["android"]["push"]["sender"] if !$app_config["android"].nil? and !$app_config["android"]["push"].nil?
    $push_sender = "support@rhomobile.com" if $push_sender.nil?

    mkdir_p $bindir if not File.exists? $bindir
    mkdir_p $rhobindir if not File.exists? $rhobindir
    mkdir_p $targetdir if not File.exists? $targetdir
    mkdir_p $srcdir if not File.exists? $srcdir
    mkdir_p $libs if not File.exists? $libs

  end
end


namespace "build" do
  namespace "android" do
 #   desc "Generate R.java file"
    task :rjava => "config:android" do

      manifest = $appmanifest
      resource = $appres
      assets = Jake.get_absolute(File.join($androidpath, "Rhodes", "assets"))
      nativelibs = Jake.get_absolute(File.join($androidpath, "Rhodes", "libs"))
      #rjava = Jake.get_absolute(File.join($androidpath, "Rhodes", "gen", "com", "rhomobile", "rhodes"))

      args = ["package", "-f", "-M", manifest, "-S", resource, "-A", assets, "-I", $androidjar, "-J", $app_rjava_dir]
      puts Jake.run($aapt, args)

      unless $?.success?
        puts "Error in AAPT"
        exit 1
      end

    end
#    desc "Build RhoBundle for android"
    task :rhobundle => ["config:android","build:bundle:noxruby",:extensions,:librhodes] do
#      Rake::Task["build:bundle:noxruby"].execute

      assets = File.join(Jake.get_absolute($androidpath), "Rhodes", "assets")
      rm_rf assets
      mkdir_p assets
      hash = nil
      ["apps", "db", "lib"].each do |d|
        cp_r File.join($srcdir, d), assets, :preserve => true
        # Calculate hash of directories
        hash = get_dir_hash(File.join(assets, d), hash)
      end
      File.open(File.join(assets, "hash"), "w") { |f| f.write(hash.hexdigest) }

      File.open(File.join(assets, "name"), "w") { |f| f.write($appname) }
      
      psize = assets.size + 1

      File.open(File.join(assets, 'rho.dat'), 'w') do |dat|
        Dir.glob(File.join(assets, '**/*')).sort.each do |f|
          relpath = f[psize..-1]

          if File.directory?(f)
            type = 'dir'
          elsif File.file?(f)
            type = 'file'
          else
            next
          end
          size = File.stat(f).size
          tm = File.stat(f).mtime.to_i

          dat.puts "#{relpath}\t#{type}\t#{size.to_s}\t#{tm.to_s}"
        end
      end
    end

    task :extensions => :genconfig do

      ENV['RHO_PLATFORM'] = 'android'
      ENV["ANDROID_NDK"] = $androidndkpath
      ENV["ANDROID_API_LEVEL"] = ANDROID_API_LEVEL.to_s
      ENV["TARGET_TEMP_DIR"] = $extensionsdir
      ENV["RHO_ROOT"] = $startdir
      ENV["BUILD_DIR"] ||= $startdir + "/platform/android/build"
      ENV["RHO_INC"] = $appincdir

      mkdir_p $extensionsdir unless File.directory? $extensionsdir

      $app_config["extensions"].each do |ext|
        $app_config["extpaths"].each do |p|
          extpath = File.join(p, ext, 'ext')
          if RUBY_PLATFORM =~ /(win|w)32$/
            next unless File.exists? File.join(extpath, 'build.bat')
          else
            next unless File.executable? File.join(extpath, 'build')
          end

          ENV['TEMP_FILES_DIR'] = File.join(ENV["TARGET_TEMP_DIR"], ext)

          if RUBY_PLATFORM =~ /(win|w)32$/
            puts Jake.run('build.bat', [], extpath)
          else
            puts Jake.run('./build', [], extpath)
          end
          exit 1 unless $?.success?
        end
      end

    end

    task :libsqlite => "config:android" do
      srcdir = File.join($shareddir, "sqlite")
      objdir = $objdir["sqlite"]
      libname = $libname["sqlite"]

      cc_build 'libsqlite', objdir, ["-I#{srcdir}"] or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libcurl => "config:android" do
      # Steps to get curl_config.h from fresh libcurl sources:
      #export PATH=<ndkroot>/build/prebuilt/linux-x86/arm-eabi-4.2.1/bin:$PATH
      #export CC=arm-eabi-gcc
      #export CPP=arm-eabi-cpp
      #export CFLAGS="--sysroot <ndkroot>/build/platforms/android-3/arch-arm -fPIC -mandroid -DANDROID -DOS_ANDROID"
      #export CPPFLAGS="--sysroot <ndkroot>/build/platforms/android-3/arch-arm -fPIC -mandroid -DANDROID -DOS_ANDROID"
      #./configure --without-ssl --without-ca-bundle --without-ca-path --without-libssh2 --without-libidn --disable-ldap --disable-ldaps --host=arm-eabi

      srcdir = File.join $shareddir, "curl", "lib"
      objdir = $objdir["curl"]
      libname = $libname["curl"]

      args = []
      args << "-DHAVE_CONFIG_H"
      args << "-I#{srcdir}/../include"
      args << "-I#{srcdir}"
      args << "-I#{$shareddir}"      

      cc_build 'libcurl', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libruby => "config:android" do
      srcdir = File.join $shareddir, "ruby"
      objdir = $objdir["ruby"]
      libname = $libname["ruby"]
      args = []
      args << "-I#{srcdir}/include"
      args << "-I#{srcdir}/linux"
      args << "-I#{srcdir}/generated"
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'libruby', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libjson => "config:android" do
      srcdir = File.join $shareddir, "json"
      objdir = $objdir["json"]
      libname = $libname["json"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'libjson', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    unless USE_STLPORT
      task :libstlport do
      end
    else
      task :libstlport => "config:android" do
        if USE_STLPORT
          objdir = $objdir["stlport"]
          libname = $libname["stlport"]

          args = []
          args << "-I#{$stlport_includes}"
          args << "-DTARGET_OS=android"
          args << "-DOSNAME=android"
          args << "-DCOMPILER_NAME=gcc"
          args << "-DBUILD_OSNAME=android"
          args << "-D_REENTRANT"
          args << "-D__NEW__"
          args << "-ffunction-sections"
          args << "-fdata-sections"
          args << "-fno-rtti"
          args << "-fno-exceptions"

          cc_build 'libstlport', objdir, args or exit 1
          cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
        end
      end
    end

    task :librholog => "config:android" do
      srcdir = File.join $shareddir, "logging"
      objdir = $objdir["rholog"]
      libname = $libname["rholog"]
      args = []
      args << "-I#{srcdir}/.."
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librholog', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhomain => "config:android" do
      srcdir = $shareddir
      objdir = $objdir["rhomain"]
      libname = $libname["rhomain"]
      args = []
      args << "-I#{srcdir}"
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librhomain', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhocommon => "config:android" do
      objdir = $objdir["rhocommon"]
      libname = $libname["rhocommon"]
      args = []
      args << "-I#{$shareddir}"
      args << "-I#{$shareddir}/curl/include"
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librhocommon', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhodb => "config:android" do
      srcdir = File.join $shareddir, "db"
      objdir = $objdir["rhodb"]
      libname = $libname["rhodb"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librhodb', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :librhosync => "config:android" do
      srcdir = File.join $shareddir, "sync"
      objdir = $objdir["rhosync"]
      libname = $libname["rhosync"]
      args = []
      args << "-I#{srcdir}"
      args << "-I#{srcdir}/.."
      args << "-I#{srcdir}/../sqlite"
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librhosync', objdir, args or exit 1
      cc_ar libname, Dir.glob(objdir + "/**/*.o") or exit 1
    end

    task :libs => [:libsqlite, :libcurl, :libruby, :libjson, :libstlport, :librhodb, :librhocommon, :librhomain, :librhosync, :librholog]

    task :genconfig => "config:android" do
      mkdir_p $appincdir unless File.directory? $appincdir

      # Generate genconfig.h
      genconfig_h = File.join($appincdir, 'genconfig.h')

      gapi_already_enabled = false
      caps_already_enabled = {}
      #ANDROID_PERMISSIONS.keys.each do |k|
      #  caps_already_enabled[k] = false
      #end
      if File.file? genconfig_h
        File.open(genconfig_h, 'r') do |f|
          while line = f.gets
            if line =~ /^\s*#\s*define\s+RHO_GOOGLE_API_KEY\s+"[^"]*"\s*$/
              gapi_already_enabled = true
            else
              ANDROID_PERMISSIONS.keys.each do |k|
                if line =~ /^\s*#\s*define\s+RHO_CAP_#{k.upcase}_ENABLED\s+(.*)\s*$/
                  value = $1.strip
                  if value == 'true'
                    caps_already_enabled[k] = true
                  elsif value == 'false'
                    caps_already_enabled[k] = false
                  else
                    raise "Unknown value for the RHO_CAP_#{k.upcase}_ENABLED: #{value}"
                  end
                end
              end
            end
          end
        end
      end

      regenerate = false
      regenerate = true unless File.file? genconfig_h
      regenerate = $use_geomapping != gapi_already_enabled unless regenerate

      caps_enabled = {}
      ANDROID_PERMISSIONS.keys.each do |k|
        caps_enabled[k] = $app_config["capabilities"].index(k) != nil
        regenerate = true if caps_already_enabled[k].nil? or caps_enabled[k] != caps_already_enabled[k]
      end

      if regenerate
        puts "Need to regenerate genconfig.h"
        $stdout.flush
        File.open(genconfig_h, 'w') do |f|
          f.puts "#ifndef RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F"
          f.puts "#define RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F"
          f.puts ""
          f.puts "#define RHO_GOOGLE_API_KEY \"#{$gapikey}\"" if $use_geomapping and !$gapikey.nil?
          caps_enabled.each do |k,v|
            f.puts "#define RHO_CAP_#{k.upcase}_ENABLED #{v ? "true" : "false"}"
          end
          f.puts ""
          f.puts "#endif /* RHO_GENCONFIG_H_411BFA4742CF4F2AAA3F6B411ED7514F */"
        end
      else
        puts "No need to regenerate genconfig.h"
        $stdout.flush
      end

      # Generate rhocaps.inc
      rhocaps_inc = File.join($appincdir, 'rhocaps.inc')
      caps_already_defined = []
      if File.exists? rhocaps_inc
        File.open(rhocaps_inc, 'r') do |f|
          while line = f.gets
            next unless line =~ /^\s*RHO_DEFINE_CAP\s*\(\s*([A-Z_]*)\s*\)\s*\s*$/
            caps_already_defined << $1.downcase
          end
        end
      end

      if caps_already_defined.sort.uniq != ANDROID_PERMISSIONS.keys.sort.uniq
        puts "Need to regenerate rhocaps.inc"
        $stdout.flush
        File.open(rhocaps_inc, 'w') do |f|
          ANDROID_PERMISSIONS.keys.sort.each do |k|
            f.puts "RHO_DEFINE_CAP(#{k.upcase})"
          end
        end
      else
        puts "No need to regenerate rhocaps.inc"
        $stdout.flush
      end

      # Generate Capabilities.java
      File.open($app_capabilities_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class Capabilities {"
        ANDROID_PERMISSIONS.keys.sort.each do |k|
          f.puts "  public static boolean #{k.upcase}_ENABLED = true;"
        end
        f.puts "}"
      end

      # Generate Push.java
      puts "app_push_java: #{$app_push_java.inspect}"
      File.open($app_push_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class Push {"
        f.puts "  public static final String SENDER = \"#{$push_sender}\";"
        f.puts "};"
      end

    end

    task :gen_java_ext => "config:android" do
      File.open($app_native_libs_java, "w") do |f|
        f.puts "package #{JAVA_PACKAGE_NAME};"
        f.puts "public class NativeLibraries {"
        f.puts "  public static void load() {"
        f.puts "    // Load native .so libraries"
        Dir.glob($extensionsdir + "/lib*.so").reverse.each do |lib|
          libname = File.basename(lib).gsub(/^lib/, '').gsub(/\.so$/, '')
          f.puts "    System.loadLibrary(\"#{libname}\");"
        end
        f.puts "    // Load native implementation of rhodes"
        f.puts "    System.loadLibrary(\"rhodes\");"
        f.puts "  }"
        f.puts "};"
      end
    end

    task :gensources => [:genconfig, :gen_java_ext]

    task :librhodes => [:libs, :gensources] do
      srcdir = File.join $androidpath, "Rhodes", "jni", "src"
      objdir = File.join $bindir, "libs", $confdir, $ndkgccver, "librhodes"
      libname = File.join $bindir, "libs", $confdir, $ndkgccver, "librhodes.so"

      args = []
      args << "-I#{$appincdir}"
      args << "-I#{srcdir}/../include"
      args << "-I#{$shareddir}"
      args << "-I#{$shareddir}/common"
      args << "-I#{$shareddir}/sqlite"
      args << "-I#{$shareddir}/curl/include"
      args << "-I#{$shareddir}/ruby/include"
      args << "-I#{$shareddir}/ruby/linux"
      args << "-D__SGI_STL_INTERNAL_PAIR_H" if USE_STLPORT
      args << "-D__NEW__" if USE_STLPORT
      args << "-I#{$stlport_includes}" if USE_STLPORT

      cc_build 'librhodes', objdir, args or exit 1

      deps = []
      $libname.each do |k,v|
        deps << v
      end

      args = []
      args << "-L#{$rhobindir}/#{$confdir}/#{$ndkgccver}"
      args << "-L#{$bindir}/libs/#{$confdir}/#{$ndkgccver}"
      args << "-L#{$extensionsdir}"

      rlibs = []
      rlibs << "rhomain"
      rlibs << "ruby"
      rlibs << "rhosync"
      rlibs << "rhodb"
      rlibs << "rholog"
      rlibs << "rhocommon"
      rlibs << "json"
      rlibs << "stlport" if USE_STLPORT
      rlibs << "curl"
      rlibs << "sqlite"
      rlibs << "log"
      rlibs << "dl"
      rlibs << "z"

      rlibs.map! { |x| "-l#{x}" }

      elibs = []
      extlibs = Dir.glob($extensionsdir + "/lib*.a") + Dir.glob($extensionsdir + "/lib*.so")
      stub = []
      extlibs.reverse.each do |f|
        lparam = "-l" + File.basename(f).gsub(/^lib/,"").gsub(/\.(a|so)$/,"")
        elibs << lparam
        # Workaround for GNU ld: this way we have specified one lib multiple times
        # command line so ld's dependency mechanism will find required functions
        # independently of its position in command line
        stub.each do |s|
          args << s
        end
        stub << lparam
      end

      args += elibs
      args += rlibs
      args += elibs
      args += rlibs

  	  mkdir_p File.dirname(libname) unless File.directory? File.dirname(libname)
      cc_link libname, Dir.glob(objdir + "/**/*.o"), args, deps or exit 1

      destdir = File.join($androidpath, "Rhodes", "libs", "armeabi")
      mkdir_p destdir unless File.exists? destdir
      cp_r libname, destdir
      cc_run($stripbin, [File.join(destdir, File.basename(libname))])
    end

 #   desc "Build Rhodes for android"
    task :rhodes => :rhobundle do
      javac = $config["env"]["paths"]["java"] + "/javac" + $exe_ext

      rm_rf $tmpdir + "/Rhodes"
      mkdir_p $tmpdir + "/Rhodes"

      set_app_name_android($appname)
      generate_rjava

      srclist = File.join($builddir, "RhodesSRC_build.files")
      newsrclist = File.join($tmpdir, "RhodesSRC_build.files")
      lines = []
      File.open(srclist, "r") do |f|
        while line = f.gets
          line.chomp!
          next if line =~ /\/AndroidR\.java\s*$/
          next if !$use_geomapping and line =~ /\/mapview\//
          lines << line
        end
      end
      lines << File.join($app_rjava_dir, "R.java")
      lines << $app_android_r
      lines << $app_native_libs_java
      lines << $app_capabilities_java
      lines << $app_push_java
      if File.exists? File.join($extensionsdir, "ext_build.files")
        puts 'ext_build.files found ! Addditional files for compilation :'
        File.open(File.join($extensionsdir, "ext_build.files")) do |f|
          while line = f.gets
            puts 'java file : ' + line
            lines << line
          end
        end
      else
        puts 'ext_build.files not found - no additional java files for compilation'
      end

      File.open(newsrclist, "w") { |f| f.write lines.join("\n") }
      srclist = newsrclist

      args = []
      args << "-g"
      args << "-d"
      args << $tmpdir + '/Rhodes'
      args << "-source"
      args << "1.6"
      args << "-target"
      args << "1.6"
      args << "-nowarn"
      args << "-encoding"
      args << "latin1"
      args << "-classpath"
      classpath = $androidjar
      classpath += $path_separator + $gapijar unless $gapijar.nil?
      classpath += $path_separator + "#{$tmpdir}/Rhodes"
      Dir.glob(File.join($extensionsdir, "*.jar")).each do |f|
        classpath += $path_separator + f
      end
      args << classpath
      args << "@#{srclist}"
      puts Jake.run(javac, args)
      unless $?.success?
        puts "Error compiling java code"
        exit 1
      end

      files = []
      Dir.glob(File.join($extensionsdir, "*.jar")).each do |f|
        puts Jake.run($jarbin, ["xf", f], File.join($tmpdir, "Rhodes"))
        unless $?.success?
          puts "Error running jar (xf)"
          exit 1
        end
      end
      Dir.glob(File.join($tmpdir, "Rhodes", "*")).each do |f|
        relpath = Pathname.new(f).relative_path_from(Pathname.new(File.join($tmpdir, "Rhodes"))).to_s
        files << relpath
      end
      unless files.empty?
        args = ["cf", "../../Rhodes.jar"]
        args += files
        puts Jake.run($jarbin, args, File.join($tmpdir, "Rhodes"))
        unless $?.success?
          puts "Error running jar"
          exit 1
        end
      end
    end

    #desc "build all"
    task :all => [:rhobundle, :rhodes]
  end
end

namespace "package" do
  task :android => "build:android:all" do
    puts "Running dx utility"
    args = []
    args << "--dex"
    args << "--output=#{$bindir}/classes.dex"
    args << "#{$bindir}/Rhodes.jar"
    puts Jake.run($dx, args)
    unless $?.success?
      puts "Error running DX utility"
      exit 1
    end

    manifest = $appmanifest
    resource = $appres
    assets = Jake.get_absolute $androidpath + "/Rhodes/assets"
    resourcepkg =  $bindir + "/rhodes.ap_"

    puts "Packaging Assets and Jars"

    set_app_name_android($appname)

    args = ["package", "-f", "-M", manifest, "-S", resource, "-A", assets, "-I", $androidjar, "-F", resourcepkg]
    puts Jake.run($aapt, args)
    unless $?.success?
      puts "Error running AAPT (1)"
      exit 1
    end

    # Workaround: manually add files starting with '_' because aapt silently ignore such files when creating package
    rm_rf File.join($tmpdir, "assets")
    cp_r assets, $tmpdir
    Dir.glob(File.join($tmpdir, "assets/**/*")).each do |f|
      next unless File.basename(f) =~ /^_/
      relpath = Pathname.new(f).relative_path_from(Pathname.new($tmpdir)).to_s
      puts "Add #{relpath} to #{resourcepkg}..."
      args = ["uf", resourcepkg, relpath]
      puts Jake.run($jarbin, args, $tmpdir)
      unless $?.success?
        puts "Error running AAPT (2)"
        exit 1
      end
    end

    # Add native librhodes.so
    rm_rf File.join($tmpdir, "lib")
    mkdir_p File.join($tmpdir, "lib/armeabi")
    cp_r File.join($bindir, "libs", $confdir, $ndkgccver, "librhodes.so"), File.join($tmpdir, "lib/armeabi")
    # Add extensions .so libraries
    Dir.glob($extensionsdir + "/lib*.so").each do |lib|
      cp_r lib, File.join($tmpdir, "lib/armeabi")
    end
    args = ["uf", resourcepkg]
    # Strip them all to decrease size
    Dir.glob($tmpdir + "/lib/armeabi/lib*.so").each do |lib|
      cc_run($stripbin, [lib])
      args << "lib/armeabi/#{File.basename(lib)}"
    end
    puts Jake.run($jarbin, args, $tmpdir)
    err = $?
    rm_rf $tmpdir + "/lib"
    unless err.success?
      puts "Error running AAPT (3)"
      exit 1
    end
  end
end

def get_app_log(appname, device, silent = false)
  pkgname = 'com.rhomobile.' + appname.downcase.gsub(/[^A-Za-z_0-9]/, '')
  path = File.join('/data/data', pkgname, 'rhodata', 'RhoLog.txt')
  cc_run($adb, [device ? '-d' : '-e', 'pull', path, $app_path]) or return false
  puts "RhoLog.txt stored to " + $app_path unless silent
  return true
end

namespace "device" do
  namespace "android" do

    desc "Build debug self signed for device"
    task :debug => "package:android" do
      dexfile =  $bindir + "/classes.dex"
      simple_apkfile =  $targetdir + "/" + $appname + "-tmp.apk"
      final_apkfile =  $targetdir + "/" + $appname + "-debug.apk"
      resourcepkg =  $bindir + "/rhodes.ap_"

      puts "Building APK file"
      Jake.run($apkbuilder, [simple_apkfile, "-z", resourcepkg, "-f", dexfile])
      unless $?.success?
        puts "Error building APK file"
        exit 1
      end

      puts "Align Debug APK file"
      args = []
      args << "-f"
      args << "-v"
      args << "4"
      args << '"' + simple_apkfile + '"'
      args << '"' + final_apkfile + '"'
      puts Jake.run($zipalign, args)
      unless $?.success?
        puts "Error running zipalign"
        exit 1
      end
      #remove temporary files
      rm_rf simple_apkfile

    end

    task :install => :debug do
      apkfile = $targetdir + "/" + $appname + "-debug.apk"
      puts "Install APK file"
      Jake.run($adb, ["-d", "install", "-r", apkfile])
      unless $?.success?
        puts "Error installing APK file"
        exit 1
      end
      puts "Install complete"
    end

    desc "Build production signed for device"
    task :production => "package:android" do
      dexfile =  $bindir + "/classes.dex"
      simple_apkfile =  $targetdir + "/" + $appname + "_tmp.apk"
      final_apkfile =  $targetdir + "/" + $appname + "_signed.apk"
      signed_apkfile =  $targetdir + "/" + $appname + "_tmp_signed.apk"
      resourcepkg =  $bindir + "/rhodes.ap_"

      puts "Building APK file"
      Jake.run($apkbuilder, [simple_apkfile, "-u", "-z", resourcepkg, "-f", dexfile])
      unless $?.success?
        puts "Error building APK file"
        exit 1
      end

      if not File.exists? $keystore
        puts "Generating private keystore..."
        mkdir_p File.dirname($keystore) unless File.directory? File.dirname($keystore)

        args = []
        args << "-genkey"
        args << "-alias"
        args << $storealias
        args << "-keyalg"
        args << "RSA"
        args << "-validity"
        args << "20000"
        args << "-keystore"
        args << $keystore
        args << "-storepass"
        args << $storepass
        args << "-keypass"
        args << $keypass
        puts Jake.run($keytool, args)
        unless $?.success?
          puts "Error generating keystore file"
          exit 1
        end
      end

      puts "Signing APK file"
      args = []
      args << "-verbose"
      args << "-keystore"
      args << $keystore
      args << "-storepass"
      args << $storepass
      args << "-signedjar"
      args << signed_apkfile
      args << simple_apkfile
      args << $storealias
      puts Jake.run($jarsigner, args)
      unless $?.success?
        puts "Error running jarsigner"
        exit 1
      end

      puts "Align APK file"
      args = []
      args << "-f"
      args << "-v"
      args << "4"
      args << '"' + signed_apkfile + '"'
      args << '"' + final_apkfile + '"'
      puts Jake.run($zipalign, args)
      unless $?.success?
        puts "Error running zipalign"
        exit 1
      end
      #remove temporary files
      rm_rf simple_apkfile
      rm_rf signed_apkfile
    end

    task :getlog => "config:android" do
      get_app_log($appname, true) or exit 1
    end
  end
end

namespace "emulator" do
  namespace "android" do
    task :getlog => "config:android" do
      get_app_log($appname, false) or exit 1
    end
  end
end


def is_emulator_running
  `#{$adb} devices`.split("\n")[1..-1].each do |line|
    return true if line =~ /^emulator/
  end
  return false
end

def is_device_running
  `#{$adb} devices`.split("\n")[1..-1].each do |line|
    return true if line !~ /^emulator/
  end
  return false
end

def run_application (target_flag)
  args = []
  args << target_flag
  args << "shell"
  args << "am"
  args << "start"
  args << "-a"
  args << "android.intent.action.MAIN"
  args << "-n"
  args << $app_package_name + "/#{JAVA_PACKAGE_NAME}.Rhodes"
  Jake.run($adb, args)
end

def application_running(flag, pkgname)
  pkg = pkgname.gsub(/\./, '\.')
  `#{$adb} #{flag} shell ps`.split.each do |line|
    return true if line =~ /#{pkg}/
  end
  false
end

namespace "run" do
  namespace "android" do
    
    task :spec => ["device:android:debug"] do
        run_emulator
        do_uninstall('-e')
        
        log_name  = $app_path + '/RhoLog.txt'
        File.delete(log_name) if File.exist?(log_name)
        
        # Failsafe to prevent eternal hangs
        Thread.new {
          sleep 1000

          if RUBY_PLATFORM =~ /windows|cygwin|mingw/
            # Windows
            `taskkill /F /IM adb.exe`
            `taskkill /F /IM emulator.exe`
          else
            `killall -9 adb`
            `killall -9 emulator`
          end
        }

        load_app_and_run

        Jake.before_run_spec
        start = Time.now

        puts "waiting for log"
      
        while !File.exist?(log_name)
            get_app_log($appname, false, true)
            sleep(1)
        end

        puts "start read log"
        
        end_spec = false
        while !end_spec do
            get_app_log($appname, false, true)
            io = File.new(log_name, "r")
        
            io.each do |line|
                #puts line
                
                end_spec = !Jake.process_spec_output(line)
                break if end_spec
            end
            io.close
            
            break unless application_running('-e', $app_package_name)
            sleep(5) unless end_spec
        end

        Jake.process_spec_results(start)        
        
        # stop app
        if RUBY_PLATFORM =~ /windows|cygwin|mingw/
          # Windows
          `taskkill /F /IM adb.exe`
          `taskkill /F /IM emulator.exe`
        else
          `killall -9 adb`
          `killall -9 emulator`
        end

        $stdout.flush
        
    end

    task :phone_spec do
      exit 1 if Jake.run_spec_app('android','phone_spec')
      exit 0
    end

    task :framework_spec do
      exit 1 if Jake.run_spec_app('android','framework_spec')
      exit 0
    end
    
    task :emulator => "device:android:debug" do
        run_emulator
        load_app_and_run
    end

    def  run_emulator
      apkfile = Jake.get_absolute $targetdir + "/" + $appname + "-debug.apk"

      Jake.run($adb, ['kill-server'])	
      #Jake.run($adb, ['start-server'])	
      #adb_start_server = $adb + ' start-server'
      Thread.new { Jake.run($adb, ['start-server']) }
      puts 'Sleep for 5 sec. waiting for "adb start-server"'
      sleep 5

      createavd = "\"#{$androidbin}\" create avd --name #{$avdname} --target #{$avdtarget} --sdcard 32M --skin HVGA"
      system(createavd) unless File.directory?( File.join(ENV['HOME'], ".android", "avd", "#{$avdname}.avd" ) )

      if $use_google_addon_api
        avdini = File.join(ENV['HOME'], '.android', 'avd', "#{$avdname}.ini")
        avd_using_gapi = true if File.new(avdini).read =~ /:Google APIs:/
        unless avd_using_gapi
          puts "Can not use specified AVD (#{$avdname}) because of incompatibility with Google APIs. Delete it and try again."
          exit 1
        end
      end

      running = is_emulator_running

      if !running
        # Start the emulator, check on it every 5 seconds until it's running
        Thread.new { system("\"#{$emulator}\" -avd #{$avdname}") }
        puts "Waiting up to 180 seconds for emulator..."
        startedWaiting = Time.now
        adbRestarts = 1
        while (Time.now - startedWaiting < 180 )
          sleep 5
          now = Time.now
          emulatorState = ""
          Jake.run2($adb,["-e", "get-state"],{:system => false, :hideerrors => :false}) do |line|
            puts "RET: " + line
            emulatorState += line
          end
          if emulatorState =~ /unknown/
            printf("%.2fs: ",(now - startedWaiting))
            if (now - startedWaiting) > (60 * adbRestarts)
              # Restart the adb server every 60 seconds to prevent eternal waiting
              puts "Appears hung, restarting adb server"
              Jake.run($adb, ['kill-server'])
              Thread.new { Jake.run($adb, ['start-server']) }
              adbRestarts += 1
            else
              puts "Still waiting..."
            end
          else
            puts "Success"
            puts "Device is ready after " + (Time.now - startedWaiting).to_s + " seconds"
            break
          end
        end

        if !is_emulator_running
          puts "Emulator still isn't up and running, giving up"
          exit 1
        end

      else
        puts "Emulator is up and running"
      end

      $stdout.flush
    end
    
    def  load_app_and_run
      puts "Loading package into emulator"
      apkfile = Jake.get_absolute $targetdir + "/" + $appname + "-debug.apk"
      count = 0
      done = false
      while count < 20
        f = Jake.run2($adb, ["-e", "install", "-r", apkfile], {:nowait => true})
        theoutput = ""
        while c = f.getc
          $stdout.putc c
          $stdout.flush
          theoutput << c
        end
        f.close

        if theoutput.to_s.match(/Success/)
          done = true
          break
        end

        puts "Failed to load (possibly because emulator not done launching)- retrying"
        $stdout.flush
        sleep 1
        count += 1
      end

      puts "Loading complete, starting application.." if done
      run_application("-e") if done
    end

    desc "build and install on device"
    task :device => "device:android:install" do
      puts "Starting application..."
      run_application("-d")
    end
  end

  desc "build and launch emulator"
  task :android => "run:android:emulator" do
  end
end

namespace "uninstall" do
  def do_uninstall(flag)
    args = []
    args << flag
    args << "uninstall"
    args << $app_package_name
    Jake.run($adb, args)
    unless $?.success?
      puts "Error uninstalling application"
      exit 1
    end

    puts "Application uninstalled successfully"
  end

  namespace "android" do
    task :emulator => "config:android" do
      unless is_emulator_running
        puts "WARNING!!! Emulator is not up and running"
        exit 1
      end
      do_uninstall('-e')
    end

    desc "uninstall from device"
    task :device => "config:android" do
      unless is_device_running
        puts "WARNING!!! Device is not connected"
        exit 1
      end
      do_uninstall('-d')
    end
  end

  desc "uninstall from emulator"
  task :android => "uninstall:android:emulator" do
  end
end

namespace "clean" do
  desc "Clean Android"
  task :android => "clean:android:all"
  namespace "android" do
    task :assets => "config:android" do
      Dir.glob($androidpath + "/Rhodes/assets/**/*") do |f|
        rm f, :force => true unless f =~ /\/loading\.html$/
      end
    end
    task :files => "config:android" do
      rm_rf $targetdir
      rm_rf $bindir
      rm_rf $srcdir
      rm_rf $libs
    end
  task :libsqlite => "config:android" do
    cc_clean "sqlite"
  end
  task :libs => ["config:android"] do
    $native_libs.each do |l|
      cc_clean l
    end
  end
  task :librhodes => "config:android" do
    rm_rf $rhobindir + "/" + $confdir + "/" + $ndkgccver + "/librhodes"
    rm_rf $bindir + "/libs/" + $confdir + "/" + $ndkgccver + "/librhodes.so"
  end
#  desc "clean android"
  task :all => [:assets,:librhodes,:libs,:files]
  end
end

