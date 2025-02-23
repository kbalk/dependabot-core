# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pip_compile_version_resolver"

namespace = Dependabot::Python::UpdateChecker
RSpec.describe namespace::PipCompileVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject do
      resolver.latest_resolvable_version(requirement: updated_requirement)
    end
    let(:updated_requirement) { ">= 17.3.0, <= 18.1.0" }

    it { is_expected.to eq(Gem::Version.new("18.1.0")) }

    context "with a mismatch in filename" do
      let(:generated_fixture_name) { "pip_compile_unpinned_renamed.txt" }
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test-funky.txt",
          content: fixture("requirements", generated_fixture_name)
        )
      end

      it { is_expected.to eq(Gem::Version.new("18.1.0")) }
    end

    context "with an upper bound" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      context "when originally unpinned" do
        let(:updated_requirement) { "<= 18.1.0" }
        it { is_expected.to eq(Gem::Version.new("18.1.0")) }
      end

      context "when not unlocking requirements" do
        let(:updated_requirement) { "<= 17.4.0" }
        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end

      context "when the latest version isn't allowed (doesn't exist)" do
        let(:updated_requirement) { "<= 18.0.0" }
        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end

      context "when the latest version is nil" do
        let(:updated_requirement) { ">= 0" }
        it { is_expected.to be >= Gem::Version.new("18.1.0") }
      end

      context "when updating is blocked" do
        let(:dependency_name) { "python-dateutil" }
        let(:dependency_version) { "2.6.1" }
        let(:dependency_requirements) do
          [{
            file: "requirements/shared.in",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          }]
        end
        let(:updated_requirement) { ">= 2.6.1, <= 2.7.5" }

        context "but only in an imported file" do
          let(:dependency_files) do
            [shared_file, manifest_file, generated_file]
          end
          let(:shared_file) do
            Dependabot::DependencyFile.new(
              name: "requirements/shared.in",
              content:
                fixture("pip_compile_files", "python_dateutil.in")
            )
          end
          let(:manifest_fixture_name) { "imports_shared.in" }
          let(:generated_fixture_name) { "pip_compile_imports_shared.txt" }

          it { is_expected.to be >= Gem::Version.new("2.6.1") }
        end
      end

      context "when unlocking causes a conflict (in the sub-dependencies)" do
        let(:manifest_fixture_name) { "unresolvable_if_unpinned.in" }
        let(:generated_fixture_name) do
          "pip_compile_unresolvable_if_unpinned.txt"
        end
        let(:dependency_name) { "boto3" }
        let(:dependency_version) { "1.7.84" }
        let(:updated_requirement) { ">= 1.7.84, <= 1.9.28" }
        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: ">=1.7,<1.8",
            groups: [],
            source: nil
          }]
        end
        it { is_expected.to be nil }

        context "and updating would cause a conflict" do
          let(:dependency_name) { "moto" }
          let(:dependency_version) { "1.3.6" }
          let(:updated_requirement) { ">= 1.3.6, <= 1.3.7" }

          let(:dependency_requirements) do
            [{
              file: "requirements/test.in",
              requirement: nil,
              groups: [],
              source: nil
            }]
          end
          it { is_expected.to be nil }
        end
      end

      context "with multiple requirement.in files" do
        let(:dependency_files) do
          [manifest_file, manifest_file2, generated_file, generated_file2]
        end

        let(:manifest_file2) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.in",
            content:
              fixture("pip_compile_files", manifest_fixture_name2)
          )
        end
        let(:generated_file2) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.txt",
            content: fixture("requirements", generated_fixture_name2)
          )
        end
        let(:manifest_fixture_name2) { manifest_fixture_name }
        let(:generated_fixture_name2) { generated_fixture_name }

        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }, {
            file: "requirements/dev.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be >= Gem::Version.new("18.1.0") }

        context "one of which is not resolvable" do
          let(:manifest_fixture_name2) { "unresolvable.in" }

          it "raises a helpful error" do
            expect { subject }.
              to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
                expect(error.message).
                  to start_with("Could not find a version that matches boto3")
              end
          end
        end
      end
    end

    context "with an unresolvable requirement" do
      let(:manifest_fixture_name) { "unresolvable.in" }
      let(:dependency_files) { [manifest_file] }
      let(:dependency_name) { "boto3" }
      let(:dependency_version) { nil }
      let(:updated_requirement) { ">= 0, <= 1.9.28" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "==1.9.27",
          groups: [],
          source: nil
        }]
      end

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).
              to start_with("Could not find a version that matches boto3")
          end
      end
    end

    context "with an unresolvable project" do
      let(:dependency_files) { project_dependency_files("unresolvable") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "jupyter-server",
          version: "0.1.1",
          requirements: dependency_requirements,
          package_manager: "pip"
        )
      end
      let(:dependency_requirements) do
        [{
          file: "requirements.in",
          requirement: nil,
          groups: [],
          source: nil
        }]
      end

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).
              to start_with("Could not find a version that matches jupyter-server")
          end
      end
    end

    context "with a git source" do
      context "for another dependency, that can't be reached" do
        let(:manifest_fixture_name) { "git_source_unreachable.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_version) { nil }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
              expect(error.dependency_urls).
                to eq(["https://github.com/greysteil/unreachable"])
            end
        end
      end

      context "for another dependency, that has a bad ref" do
        let(:manifest_fixture_name) { "git_source_bad_ref.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_version) { nil }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency).to eq("pythonfinder")
            end
        end
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "pbr" }
      let(:dependency_version) { "4.0.2" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">= 4.0.2, <= 4.3.0" }

      it { is_expected.to eq(Gem::Version.new("4.3.0")) }

      context "that is superfluous" do
        let(:dependency_name) { "requests" }
        let(:dependency_version) { "2.18.0" }
        let(:dependency_requirements) { [] }
        let(:updated_requirement) { ">= 2.18.0, <= 2.18.4" }
        let(:generated_fixture_name) { "pip_compile_unpinned_rogue.txt" }

        it { is_expected.to be_nil }
      end
    end

    context "with a dependency that is 'unsafe' to lock" do
      let(:manifest_fixture_name) { "setuptools.in" }
      let(:generated_fixture_name) { "pip_compile_setuptools.txt" }
      let(:dependency_name) { "setuptools" }
      let(:dependency_version) { "40.4.1" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">= 40.4.1" }

      it { is_expected.to be >= Gem::Version.new("40.6.2") }
    end

    context "with an import of the setup.py" do
      let(:dependency_files) do
        [manifest_file, generated_file, setup_file, pyproject]
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("setup_files", setup_fixture_name)
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "black_configuration.toml")
        )
      end
      let(:manifest_fixture_name) { "imports_setup.in" }
      let(:generated_fixture_name) { "pip_compile_imports_setup.txt" }
      let(:setup_fixture_name) { "small.py" }
      let(:dependency_name) { "attrs" }
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: nil,
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("18.1.0") }

      context "that needs sanitizing" do
        let(:setup_fixture_name) { "small_needs_sanitizing.py" }
        it { is_expected.to be >= Gem::Version.new("18.1.0") }
      end
    end

    context "with a Python 2.7 library" do
      let(:manifest_fixture_name) { "legacy_python.in" }
      let(:generated_fixture_name) { "pip_compile_legacy_python.txt" }

      let(:dependency_name) { "wsgiref" }
      let(:dependency_version) { "0.1.1" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=0.1.2",
          groups: [],
          source: nil
        }]
      end
      let(:updated_requirement) { ">= 0.1.1, <= 2.0.0" }

      it { is_expected.to eq(Gem::Version.new("0.1.2")) }

      context "that uses markers correctly (so raises a different error)" do
        let(:manifest_fixture_name) { "legacy_python_2.in" }
        let(:generated_fixture_name) { "pip_compile_legacy_python_2.txt" }

        let(:dependency_name) { "astroid" }
        let(:dependency_version) { "1.6.4" }
        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<2",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(Gem::Version.new("1.6.6")) }
      end

      context "that has swapped syntax in the latest setup.py" do
        let(:manifest_fixture_name) { "legacy_python_3.in" }
        let(:generated_fixture_name) { "pip_compile_legacy_python_3.txt" }

        let(:dependency_name) { "django-adv-cache-tag" }
        let(:dependency_version) { "0.2.1" }
        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "==0.2.1",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_nil }
      end

      context "that has a .python-version file" do
        let(:dependency_files) do
          [manifest_file, generated_file, python_version_file]
        end
        let(:python_version_file) do
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: "2.7.18\n"
          )
        end

        it { is_expected.to eq(Gem::Version.new("0.1.2")) }

        context "that has a bad version in it" do
          let(:python_version_file) do
            Dependabot::DependencyFile.new(
              name: ".python-version",
              content: "rubbish\n"
            )
          end

          it { is_expected.to eq(Gem::Version.new("0.1.2")) }
        end
      end
    end

    context "with native dependencies that are not pre-built" do
      let(:manifest_fixture_name) { "native_dependencies.in" }
      let(:generated_fixture_name) { "pip_compile_native_dependencies.txt" }
      let(:dependency_name) { "cryptography" }
      let(:dependency_version) { "2.2.2" }
      let(:updated_requirement) { "> 3.0.0" }

      it { is_expected.to eq(Gem::Version.new("3.2.1")) }
    end
  end

  describe "#resolvable?" do
    subject { resolver.resolvable?(version: version) }
    let(:version) { Gem::Version.new("18.1.0") }

    context "that is resolvable" do
      let(:version) { Gem::Version.new("18.1.0") }
      it { is_expected.to eq(true) }

      context "with a subdependency" do
        let(:dependency_name) { "pbr" }
        let(:dependency_version) { "4.0.2" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("5.1.3") }

        it { is_expected.to eq(true) }
      end
    end

    context "that is not resolvable" do
      let(:version) { Gem::Version.new("99.18.4") }
      it { is_expected.to eq(false) }

      context "with a subdependency" do
        let(:manifest_fixture_name) { "requests.in" }
        let(:generated_fixture_name) { "pip_compile_requests.txt" }
        let(:dependency_name) { "urllib3" }
        let(:dependency_version) { "1.22" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("1.23") }

        it { is_expected.to eq(false) }
      end

      context "because the original manifest isn't resolvable" do
        let(:manifest_fixture_name) { "unresolvable.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_name) { "boto3" }
        let(:dependency_version) { nil }
        let(:version) { "1.9.28" }
        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "==1.9.27",
            groups: [],
            source: nil
          }]
        end

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to start_with("Could not find a version that matches boto3")
            end
        end
      end
    end
  end
end
