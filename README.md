# miq-Utilities
ManageIQ Automate Domain of shared utilities to be used by other ManageIQ domains.

# Table of Contents
* [miq-Utilities](#miq-utilities)
* [Table of Contents](#table-of-contents)
* [Features](#features)
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
  * `Infrastructure/VM/Provisioning/Naming/vmname` implimentation with support for variable suffix counter length and specified domain name
  * Provision complete email with hostname ands IPs
  * Provision new VM(s) to an existing service
* Logging helpers

# Install
0. Install dependencies
1. Automate -> Import/Export
2. Import Datastore via git
3. Git URL: `https://github.com/rhtconsulting/miq-Utilities.git`
4. Submit
5. Select Branc/Tag to syncronize with
6. Submit
