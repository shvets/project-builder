require 'bundler/inline'
require 'yaml'
require 'json'

gemfile do
  source 'https://rubygems.org'
  gem 'script_executor'
end

require 'executable'

class ProjectBuilder
  PLIST_BUDDY = "/usr/libexec/PlistBuddy"
  FRAMEWORKS_DIR = "Frameworks"
  SWIFT_LIBS_ROOT_DIR = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift"
  SWIFT_RUNTIME_LIBS = %w(
    libswiftCore.dylib
    libswiftCoreFoundation.dylib
    libswiftCoreGraphics.dylib
    libswiftCoreImage.dylib
    libswiftDarwin.dylib
    libswiftDispatch.dylib
    libswiftFoundation.dylib
    libswiftMetal.dylib
    libswiftObjectiveC.dylib
    libswiftQuartzCore.dylib
    libswiftSwiftOnoneSupport.dylib
    libswiftUIKit.dylib
    libswiftos.dylib
  )

  OS_MAP = {
      iphoneos: {
          arch: "arm64-apple-ios12.0",
          simulator_arch: "x86_64-apple-ios12.0-simulator",
          simulator: "iphonesimulator"
      },

      tvos: {

      }
  }

  def initialize(envFile, source_dir, building_for_device)
    config = JSON.parse(JSON.dump(YAML.load_file(envFile)), symbolize_names: true)

    @project_name = config[:project_name]
    @team_identifier = config[:team_identifier]
    @identity = config[:identity]
    @provisioning_profile_name = config[:provisioning_profile_name]
    @type = config[:type]
    @building_for_device = building_for_device

    @app_bundle_identifier = "#{config[:namespace]}.#{config[:project_name]}"

    @bundle_dir = "dist/" + config[:project_name] + ".app"
    @temp_dir = "dist/" + "_BuildTemp"

    @source_dir = source_dir

    @swift_libs_src_dir = "#{SWIFT_LIBS_ROOT_DIR}/#{@type}"

    @swift_libs_dest_dir = "#{@bundle_dir}/#{FRAMEWORKS_DIR}"

    @executor = ScriptExecutor.new

    if @building_for_device
      @target = "arm64-apple-ios12.0"
      @sdk_path = %x[xcrun --show-sdk-path --sdk #{@type}]
      @other_flags = "-Xlinker -rpath -Xlinker @executable_path/#{FRAMEWORKS_DIR}"
    else
      @target = "x86_64-apple-ios12.0-simulator"
      @sdk_path = %x[xcrun --show-sdk-path --sdk #{get_simulator(@type)}]
      @other_flags = ""
    end
  end

  def build
    if @building_for_device
      print "👍 Building #{@project_name} for device"
    else
      print "👍 Building #{@project_name} for simulator "
    end

    prepare_working_folders

    compile_sources

    compile_storyboards

    process_and_copy_plist

    if !@building_for_device
      print "🎉 Building #{@project_name} for simulator successfully finished! 🎉"
    else
      copy_runtime_libraries

      sign_code
    end
  end

  def prepare_working_folders
    @executor.execute do
      %Q(
        #############################################################
        echo → Step 1: Prepare Working Folders
        #############################################################

        rm -rf dist
        rm -rf #{@temp_dir}

        mkdir dist
        mkdir #{@bundle_dir}
        echo ✅ Create #{@bundle_dir} folder

        mkdir #{@temp_dir}
        echo ✅ Create #{@temp_dir} folder
      )
    end
  end

  def compile_sources
    sources = Dir.glob("#{@source_dir}/**/*.swift").join(" ")

    target = "x86_64-apple-ios12.0-simulator"
    sdk_path = %x[xcrun --show-sdk-path --sdk iphonesimulator]
    other_flags = ""

    @executor.execute do
      %Q(
        #############################################################
        echo → Step 2: Compile Swift Files
        #############################################################

        echo #{sources}

        swiftc  #{sources} -sdk #{sdk_path.chomp} -target #{target} -emit-executable #{other_flags} -o #{@bundle_dir}/#{@project_name}

        echo ✅ Compile Swift source files #{sources}
      )
    end
  end

  def compile_storyboards
    print "echo → Step 3: Compile Storyboards"

    storyboards = Dir.glob("#{@source_dir}/Base.lproj/**/*.storyboard")

    storyboard_out_dir = "#{@bundle_dir}/Base.lproj"

    storyboards.each do |storyboard|
      @executor.execute do
        %Q(
          #############################################################
          echo → Step 3: Compile Storyboards
          #############################################################

          mkdir -p #{storyboard_out_dir}

          echo ✅ Create ${STORYBOARD_OUT_DIR} folder

          ibtool #{storyboard} --compilation-directory #{storyboard_out_dir}

          echo ✅ Compile #{storyboard}
        )
      end
    end
  end

  def process_and_copy_plist
    original_info_plist = "#{@source_dir}/Info.plist"
    temp_info_plist = "#{@temp_dir}/Info.plist"
    processed_info_plist = "#{@bundle_dir}/Info.plist"

    @executor.execute do
      %Q(
        #############################################################
        echo → Step 4: Process and Copy Info.plist
        #############################################################

        cp #{original_info_plist} #{temp_info_plist}
        #{PLIST_BUDDY} -c "Set :CFBundleExecutable #{@project_name}" #{temp_info_plist}
        #{PLIST_BUDDY} -c "Set :CFBundleIdentifier #{@app_bundle_identifier}" #{temp_info_plist}
        #{PLIST_BUDDY} -c "Set :CFBundleName #{@project_name}" #{temp_info_plist}

        cp #{temp_info_plist} #{processed_info_plist}
      )
    end
  end

  def copy_runtime_libraries
    @executor.execute do
      %Q(
        #############################################################
        echo → Step 5: Copy Swift Runtime Libraries
        #############################################################

        mkdir -p #{@bundle_dir}/#{FRAMEWORKS_DIR}
        echo ✅ Create #{@swift_libs_dest_dir} folder
      )
    end

    SWIFT_RUNTIME_LIBS.each do |library|
      @executor.execute do
        %Q(
          cp #{@swift_libs_src_dir}/#{library} #{@swift_libs_dest_dir}/

          echo ✅ Copy #{library} to #{@swift_libs_dest_dir}
        )
      end
    end
  end

  def sign_code
    embedded_provisioning_profile = "#{@bundle_dir}/embedded.mobileprovision"

    xcent_file = "#{@temp_dir}/#{@project_name}.xcent"

    @executor.execute do
      %Q(
        #############################################################
        echo → Step 6: Code Signing
        #############################################################

        cp ~/Library/MobileDevice/Provisioning\\ Profiles/#{@provisioning_profile_name} #{embedded_provisioning_profile}
        echo ✅ Copy provisioning profile #{@provisioning_profile_name} to #{embedded_provisioning_profile}

        #{PLIST_BUDDY} -c "add :application-identifier string #{@team_identifier}.#{@app_bundle_identifier}" #{xcent_file}
        #{PLIST_BUDDY} -c "add :com.apple.developer.team-identifier string #{@team_identifier}" #{xcent_file}
        #{PLIST_BUDDY} -c "add :get-task-allow bool true" #{xcent_file}

        echo ✅ Create #{xcent_file}
      )
    end

    # Sign all libraries in the bundle

    Dir.glob("#{@swift_libs_dest_dir}/*.dylib").each do |lib|
      @executor.execute do
        %Q(
          codesign --force --timestamp=none --sign #{@identity} #{lib}
          echo ✅ Codesign #{lib}
        )
      end
    end

    # Sign the bundle itself

    @executor.execute do
      %Q(
        # Sign the bundle itself
        codesign  --force --timestamp=none --sign #{@identity} --entitlements #{xcent_file} #{@bundle_dir}

        echo ✅ Codesign #{@bundle_dir}
        echo 🎉 Building #{@project_name} for device successfully finished! 🎉
      )
    end
  end

  def get_simulator type
    case type
      when "iphoneos" then
        "iphonesimulator"
      when "tvos" then
        "tvsimulator"
    end
  end
end

envFile = ENV['HOME'] + "/Dropbox/Projects/swift/.env"

builder = ProjectBuilder.new envFile, "Sources", true
builder.build

