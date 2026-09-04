# Standalone check of the rpmvercmp helpers used by find_yum_kernel_packages.
#
# Runnable with plain `ruby test/unit/rpm_evr_test.rb`, no Foreman or Katello
# needed. That matters because the full plugin suite requires a Foreman checkout,
# which is not available where this patch gets built.
#
# It extracts the two methods from the shipped source and evals them, rather than
# holding its own copy of the algorithm. A copy would let the test keep passing
# while the code it claims to cover drifts away from it.
#
# Cases are real NEVRAs taken from `rpm -q` on fleet hosts, plus the edge cases
# that decide whether a rewrite is correct or destructive.

SOURCE = File.expand_path(
  '../../app/models/concerns/foreman_kernel_care/host_managed_extensions.rb', __dir__
)

module Evr
  src = File.read(SOURCE)
  %w[rpm_evr_older? rpm_vercmp installed_older? package_epoch].each do |name|
    body = src[/^    def #{Regexp.escape(name)}.*?^    end$/m]
    raise "could not extract #{name} from #{SOURCE}" if body.nil?

    module_eval(body.gsub(/^    /, ''))
  end
  module_function :rpm_evr_older?, :rpm_vercmp, :installed_older?, :package_epoch
end

# Stands in for Katello::InstalledPackage. The no-epoch variant exists because
# package_epoch guards with respond_to?, and that guard is the thing that keeps
# this working if the model ever drops the column.
Pkg = Struct.new(:name, :version, :release, :epoch)
NoEpochPkg = Struct.new(:name, :version, :release)

# [installed_v, installed_r, target_v, target_r, expected_older?, description]
CASES = [
  # --- real ground truth from an el8 host (target 4.18.0-553.144.1.el8_10)
  ['4.18.0', '553.136.1.el8_10', '4.18.0', '553.144.1.el8_10', true,  'kernel-tools laggard -> rewrite'],
  ['4.18.0', '553.16.1.el8_10',  '4.18.0', '553.144.1.el8_10', true,  'old kernel 16.1 (numeric 16<144)'],
  ['4.18.0', '553.63.1.el8_10',  '4.18.0', '553.144.1.el8_10', true,  'running kernel -> rewrite'],
  ['4.18.0', '553.144.1.el8_10', '4.18.0', '553.144.1.el8_10', false, 'already at target -> skip'],
  # --- real ground truth from an el9 host (target 5.14.0-687.29.1.el9_8)
  ['5.14.0', '162.6.1.el9_1',    '5.14.0', '687.29.1.el9_8',   true,  'ancient kernel -> rewrite'],
  ['5.14.0', '284.30.1.el9_2',   '5.14.0', '687.29.1.el9_8',   true,  'running kernel + kernel-tools'],
  ['5.14.0', '687.29.1.el9_8',   '5.14.0', '687.29.1.el9_8',   false, 'already at target -> skip'],
  # --- no-downgrade guard
  ['5.14.0', '687.31.1.el9_8',   '5.14.0', '687.29.1.el9_8',   false, 'host NEWER than patched -> skip'],
  ['5.14.0', '687.30.1.el9_8',   '5.14.0', '687.29.1.el9_8',   false, 'host newer by one -> skip'],
  # --- dist-tag present/absent on either side
  ['4.18.0', '553.136.1.el8_10', '4.18.0', '553.144.1',        true,  'target lacks dist tag'],
  ['4.18.0', '553.144.1.el8_10', '4.18.0', '553.144.1',        false, 'installed tagged == target untagged -> skip'],
  ['4.18.0', '553.144.1',        '4.18.0', '553.144.1.el8_10', true,  'installed untagged vs tagged target'],
  # --- CentOS 7 tuxcare, the case a naive comparator gets backwards
  ['3.10.0', '1160.118.1.el7',   '3.10.0', '1160.144.1.el7.tuxcare', true, 'el7 -> tuxcare kernel'],
  ['3.10.0', '1160.el7',         '3.10.0', '1160.118.1.el7',   true,  'bare 1160.el7 IS older (digit>alpha)'],
  ['3.10.0', '1160.144.1.el7.tuxcare', '3.10.0', '1160.118.1.el7', false, 'tuxcare newer -> skip'],
  # --- version-level differences
  ['4.18.0', '553.144.1.el8_10', '5.14.0', '687.29.1.el9_8',   true,  'major version older'],
  ['5.14.0', '687.29.1.el9_8',   '4.18.0', '553.144.1.el8_10', false, 'major version newer -> skip'],
  # --- el10
  ['6.12.0', '211.22.1.el10_2',  '6.12.0', '211.38.1.el10_2',  true,  'el10 laggard'],
].freeze

fail_count = 0
CASES.each do |iv, ir, tv, tr, expected, desc|
  got = Evr.rpm_evr_older?(iv, ir, tv, tr)
  ok  = got == expected
  fail_count += 1 unless ok
  printf("  %-5s %-46s  %s-%s vs %s-%s => %s\n",
         ok ? 'PASS' : 'FAIL', desc, iv, ir, tv, tr, got)
end
puts

# installed_older? picks the newest installed build of one package name, and
# unlike the target comparison it must honour epoch, because rpm orders on epoch
# before version. EL7's python-perf carries epoch 1.
EPOCH_CASES = [
  [Pkg.new('python-perf', '3.10.0', '962.3.2.lve1.5.89.el7', 1),
   Pkg.new('python-perf', '3.10.0', '1160.144.1.el7.tuxcare.els6', 1),
   true,  'same epoch, release decides'],
  [Pkg.new('kernel', '3.10.0', '1160.144.1.el7', 0),
   Pkg.new('kernel', '3.10.0', '1160.95.1.el7', 1),
   true,  'higher epoch wins even with an older version'],
  [Pkg.new('kernel', '3.10.0', '1160.95.1.el7', 1),
   Pkg.new('kernel', '3.10.0', '1160.144.1.el7', 0),
   false, 'lower epoch loses even with a newer version'],
  [Pkg.new('python-perf', '3.10.0', '962.3.2.el7', nil),
   Pkg.new('python-perf', '3.10.0', '1160.144.1.el7', 1),
   true,  'nil epoch treated as 0'],
  [NoEpochPkg.new('kernel', '3.10.0', '1160.95.1.el7'),
   NoEpochPkg.new('kernel', '3.10.0', '1160.144.1.el7'),
   true,  'model without an epoch column still compares'],
].freeze

EPOCH_CASES.each do |older, newer, expected, desc|
  got = Evr.installed_older?(older, newer)
  ok  = got == expected
  fail_count += 1 unless ok
  printf("  %-5s %-46s  %s => %s\n", ok ? 'PASS' : 'FAIL', desc,
         "#{Evr.package_epoch(older)}:#{older.release} vs #{Evr.package_epoch(newer)}:#{newer.release}", got)
end

total = CASES.size + EPOCH_CASES.size
puts
puts fail_count.zero? ? "ALL #{total} CASES PASS" : "#{fail_count} of #{total} FAILED"
exit(fail_count.zero? ? 0 : 1)
