FactoryBot.modify do
  factory :host do
    trait :debian_with_kernelcare do
      after(:create) do |host|
        installed_deb_id = ::Katello::InstalledDeb.find_or_create_by(name: 'kernelcare',
                                                                     architecture: 'x86_64',
                                                                     version: '2.54-1').id
        host.installed_deb_ids = installed_deb_id
        host.save!
      end
    end
    trait :with_kernelcare do
      after(:create) do |host|
        package_json = {
          :name => 'kernelcare',
          :version => '2.54',
          :release => '1.el7',
          :arch => 'x86_64',
          :epoch => '1',
          :nvra => 'kernelcare-2.54-1.el7.x86_64'
        }
        host.import_package_profile([::Katello::Pulp::SimplePackage.new(package_json)])
      end
    end
  end
end
