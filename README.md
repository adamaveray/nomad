Nomad
=====

A Vagrant VMs manager. It's written in PHP.


Install
-------

Run the following command in your terminal to install Nomad:

```bash
curl -o /usr/local/bin/nomad https://raw.github.com/adamaveray/nomad/master/nomad && chmod +x /usr/local/bin/nomad
```

If you want to do the above manually, copy the `nomad` file to your bin directory (eg `/usr/local/bin`), and ensure it is executable (`chmod +x /usr/local/bin/nomad).


Usage
------

To use Nomad, you must first register any Vagrant VMs you want to use:

```bash
$ nomad add example "path/to/vagrant"
```

Then, you can call any Vagrant command through Nomad to one of the registered VMs:

```bash
$ nomad example up
```

If you have a [multi-machine setup](http://docs.vagrantup.com/v2/multi-machine/) for one of your VMs, you can still address the sub-machines like normal:

```bash
$ nomad example up web
$ nomad example halt db
```
