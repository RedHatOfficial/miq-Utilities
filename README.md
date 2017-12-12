# miq-Utilities
ManageIQ Automate Domain of shared utilities to be used by other ManageIQ domains.

# Table of Contents
* [miq-Utilities](#miq-utilities)
* [Table of Contents](#table-of-contents)
* [Features](#features)
* [Automate](#automate)
* [Install](#install)
* [Contributors](#contributors)

# Features
The high level features of this ManageIQ extension.

* Service
  * Thread safe (multiple simultaneous provisions) set VM names method with user provided prefix for use with service provisoning state machine
* VM
  * set custom attributes
  * set tags
  * start
  * VMWare DRS cluster best fit with scope placement
  * VMWare customized folder placement
* Service
  * `Infrastructure/VM/Provisioning/Naming/vmname` implementation with support for variable suffix counter length and specified domain name
  * Provision complete email with hostname ands IPs
  * Provision new VM(s) to an existing service
  * Resize primary VM disk
  * Add additional disks to VM
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

# Install
0. Install dependencies
1. Automate -> Import/Export
2. Import Datastore via git
3. Git URL: `https://github.com/rhtconsulting/miq-Utilities.git`
4. Submit
5. Select Branch/Tag to synchronize with
6. Submit
