module ForemanKernelCare
  module ProfilesUploader
    extend ActiveSupport::Concern

    def import_deb_package_profile(profile)
    if @host.kernelcare?
        composer = ::JobInvocationComposer.for_feature(:kernel_version, @host)
        composer.triggering.mode = :future
        composer.trigger!
      end

      super(profile)
    end
  end
end
