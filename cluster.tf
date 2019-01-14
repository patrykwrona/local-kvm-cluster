# Instance the provider - local KVM/QEMU connection
provider "libvirt" {
  uri = "qemu:///system"
}

# Number of instances to create
variable "number_of_instances" {
  description = "How many machines to create"
  default     = 3
}

# Instance disk
variable "instance_disk_size" {
  description = "Disk size of instance in GB"
  default     = 5 # in GB
}

# We fetch the latest ubuntu release image from their mirrors and create base image
resource "libvirt_volume" "ubuntu_base_image" {
  name   = "ubuntu_1804_base_image"
  pool   = "libvirt_pool" # name of resource pool in libvirt
  source = "https://cloud-images.ubuntu.com/releases/bionic/release/ubuntu-18.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

# Volumes to attach to the machines as their main disks
resource "libvirt_volume" "terra_disk" {
  name           = "terra_disk-${count.index}"
  base_volume_id = "${libvirt_volume.ubuntu_base_image.id}"
  count          = "${var.number_of_instances}"
  pool           = "libvirt_pool" # name of resource pool in libvirt
  format         = "qcow2"
  size           = "${var.instance_disk_size * 1024 * 1024 * 1024}"
}

# Create a network for our VMs
resource "libvirt_network" "terra_network" {
  name      = "terra_network"
  addresses = ["10.50.0.0/24"]
  mode      = "nat"
  autostart = "true"
  # dhcp {
  #   enabled = true
  # }
}

# Use CloudInit to add our ssh-key to the instance
resource "libvirt_cloudinit_disk" "terra_commoninit" {
  name      = "terra_commoninit.iso"
  pool      = "libvirt_pool" # name of resource pool in libvirt
  user_data = "${data.template_file.user_data.rendered}"
}

# Get CloudInit config from file in our terraform code directory
data "template_file" "user_data" {
  template = "${file("${path.module}/ubuntu-cloud-config.cfg")}"
}

# Create the machines (in KVM called domain)
resource "libvirt_domain" "terra_machine" {
  count = "${var.number_of_instances}"
  name = "terra_host${count.index}"
  memory = "1024" # in MB
  vcpu = 1

# Network adapter
  network_interface {
    hostname = "terra_net_if_${count.index}"
    network_id = "${libvirt_network.terra_network.id}"
    addresses = ["10.50.0.${count.index + 100}"]
  }

  cloudinit = "${libvirt_cloudinit_disk.terra_commoninit.id}"

  disk {
    volume_id = "${element(libvirt_volume.terra_disk.*.id, count.index)}"
  }

  # IMPORTANT
  # Ubuntu can hang if a isa-serial is not present at boot time.
  # If you find your CPU 100% and never is available this is why
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
      type        = "pty"
      target_type = "virtio"
      target_port = "1"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = "true"
  }


# Install python3 and wait for server to be ready - actually this is only to wait when SSH on server will be ready
  provisioner "remote-exec" {
    inline = [
      "touch i-am-remote-exec"
    ]

    connection {
      host        = "10.50.0.${count.index + 100}"
      type        = "ssh"
      user        = "pw"
      password    = "toor123"
#      private_key = "${file('~/.ssh/id_rsa')}"
    }
  }

# Run ansible from local host (laptop)
  provisioner "local-exec" {
#    environment {
#      PUBLIC_IP  = "${self.ipv4_address}"
#      PRIVATE_IP = "${self.ipv4_address_private}"
#    }

    working_dir = "./ansible/"
    command     = "ansible-playbook -u pw -i 10.50.0.${count.index + 100} setup.yml -e 'ansible_user=pw ansible_ssh_pass=toor123 ansible_sudo_pass=toor123' "
  }

}

