# miq-Utilities
ManageIQ Automate Domain of shared utilities to be used by other ManageIQ domains.

# Table of Contents
* [miq-Utilities](#miq-utilities)
* [Table of Contents](#table-of-contents)
* [Features](#features)
* [Automate](#automate)
* [Automate StdLib](#automate-stdlib)
* [Automate Settings](#automate-settings)
* [Install](#install)
* [Unit Testing](#unittesting)
* [Branches and Tags](#branches-and-tags)
* [Contributors](#contributors)

# Features
The high level features of this ManageIQ extension.

* Infrastructure
  * VM
    * set custom attributes
    * set tags
    * start
    * VMWare DRS cluster best fit with scope placement
    * VMWare customized folder placement
  * Providers / Clusters / Hosts
    * Dynamic dialog methods and instances for getting the LANs for the selected object and for tagging those LANs
    * Method for determining templated based on a selected location tag on providers and OS tag on templates
* Service
  * Thread safe (multiple simultaneous provisions) set VM names method with user provided prefix for use with service provisoning state machine
  * `Infrastructure/VM/Provisioning/Naming/vmname` implementation with support for variable suffix counter length and specified domain name
  * Provision complete email with hostname ands IPs
  * Provision new VM(s) to an existing service
  * Resize primary VM disk
  * Add additional disks to VM
* System
  * Dynamic Diaglog methods and instances for getting tags and tag categories
  * Methods for adding and removing tags from LANs
* Logging helpers

# Automate
Information on the provided Automate.

## ManageIQ Overrides
Instances where this domain overrides defaults provided in ManageIQ

* `Infrastructure/VM/Provisioning/Email` (Schema)
  * Override default schema values
* `Infrastructure/VM/Provisioning/Email/MiqProvision`\* (Instances)
  * Override all instances to change `method` to `MiqProvision_Update` rather then event specific methods
* `Infrastructure/VM/Provisioning/Naming/vmname` (Method)
  * Override to add handling for fully qualified names with prefixes on the short name
* `Infrastructure/VM/Provisioning/StateMachines/Methods/PostProvision` (Instance)
  * Override `common_meth1` to call `process_telemetry_data` 
* `Infrastructure/VM/Provisioning/StateMachines/ProvisionRequestApproval/Default` (Instance)
  * Override `max_vms` to 10
* `Infrastructure/VM/Provisioning/StateMachines/VMProvision_VM/update_provision_status` (Method)
  * Override to send email on error update
  * Override to be able to send email on any update
  * Override to collect Telemetry data on every invocation based on current step name and `ae_status_step`
* `Infrastructure/VM/Retirement/Email/`\* (Instances)
  * Override all instances attributes to be cleaner
* `Infrastructure/VM/Retirement/Email/vm_retirement_emails` (Method)
  * Override to make retirment email prettier
* `Infrastructure/VM/Retirement/StateMachines/Methods/check_pre_retirement`
  * Override to remove `unknown` from list of power states to stop looping for 
* `Infrastructure/VM/Retirement/StateMachines/Methods/check_removed_from_provider` (Method)
  * Override to add debug loggin
* `Service/Provisioning/Email/`\* (Instances)
  * Override all instances to change `method1` to `ServiceProvision_Update` rather then event specific methods
* `Service/Provisioning/StateMachines/ServiceProvision_Template/CatalogItemInitialization` (Instance)
  * Override `post5` step to call `/Service/Provisioning/StateMachines/Methods/ProcessTelemetryData`
* `Service/Provisioning/StateMachines/ServiceProvision_Template/update_serviceprovision_status` (Method)
  * Override to send email on error update
  * Override to be able to send email on any update
  * Override to collect Telemetry data on every invocation based on current step name and `ae_status_step`

## Automate StdLib

This namespace serves as a "standard library" of CloudForms (ManageIQ)
Automation code. The goal is for common methods to be collected here,
and to be suitbale for inclusion as "Embedded Methods".

See: https://cloudformsblog.redhat.com/2018/04/17/embedded-methods/ for
conceptual background.

## Automate Settings

This project now includes a new mechanism for storing and accessing configuration settings. This has some
advantages over traditional processes for configuration (instance variables or constants within a method). The
settings can all be stored in one location, and being code, edited in something more featureful than a text box.
The settings values can be any ruby data structure directly, and do not require juggling between yaml or json as
commonly happens. Additionally, as the settings are grouped into global/default/region, then one can configure
common and region-specific settings in a single place, for multi region deployments, useful for either a
replication setup, or a dev/prod envionment split, pulling code from one git source.

/StdLib/Settings/settings provides the core lookup functionality.
/StdLib/Settings/settingsstore holds setting values.


### Settings over multiple Domains

To leverage your own custom settings, one can simply copy settings.rb up to a top priority domain, and edit
it per norm. However, to isolate out ones own domain's settings, there is a mechanism ot merge in settings from
different files.

Using the commented code in settings.rb as a template, create a new (ruby) class that extends RedHatConsulting_Utilities::StdLib::Core::Settings
and has a PRIORITY and SETTINGS class values.

Copy our settings.rb to a high priority domain. Configure it to have embedded methods of all other settings.rb you wish
to include (but not the one from this project). Ordered inclusion is impossible to guarantee with the UX currently,
the PRIORITY setting, however, is honoured in merging the hashes. In practice, you are going to want to use
non-overlapping key values, or manually reconcile  the desired values in the settings.rb in the high priority domain.


# Provision Dialogs

* `miq_provision_redhat_dialogs_template_no_required_fields`
  * a clone of `miq_provision_redhat_dialogs_template` only with all required fields set to not required. This is useful when calling `create_provision_request` and not wanting to pass in all fields and rather determining them later. For example determining the `vlan` bassed on placement rather then before calling `create_provision_request`.
* miq_provision_vmware_dialogs_template_no_required_fields.yaml
  * a clone of `miq_provision_vmware_dialogs_template` only with all required fields set to not required. This is useful when calling `create_provision_request` and not wanting to pass in all fields and rather determining them later. For example determining the `vlan` bassed on placement rather then before calling `create_provision_request`.

# Install
0. Install dependencies
1. Automate -> Import/Export
2. Import Datastore via git
3. Git URL: `https://github.com/rhtconsulting/miq-Utilities.git`
4. Submit
5. Select Branch/Tag to synchronize with
6. Submit

# Unit Testing
To run the test suite, you first require a functional ManageIQ
development environment, specifically, able to run the test suite of
https://github.com/ManageIQ/manageiq-content/ . Link in this project
to that, per

manageiq-content/content/automate/RedHatConsulting_Utilities -> miq-Utilities/Automate/RedHatConsulting_Utilities
manageiq-content/spec/content/automate/RedHatConsulting_Utilities -> miq-Utilities/UnitTests/spec/content/RedHatConsulting_Utilities
manageiq-content/spec/factories/RedHatConsulting_Utilities -> miq-Utilities/UnitTests/spec/factories/RedHatConsulting_Utilities

and then run
$ bundle exec rake
or, e.g.,
$ bundle exec rspec --format documentation --pattern spec/content/automate/RedHatConsulting_Utilities/**/*_spec.rb

# Branches and Tags
The master branch of this repository will aim to support the current CloudForms release.
If breaking changes for previous CloudForms versions are introduced in Master, version specific branches and tags will be created for those previous versions, as long as those releases are still supported by Red Hat. The version-specific release branches will be no longer be maintained once that version of CloudForms is end of life.

CloudForms Product Lifecycle Information:
* https://access.redhat.com/support/policy/updates/cloudforms

# Contributors
https://github.com/RedHatOfficial/miq-Utilities/graphs/contributors
