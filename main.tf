data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = var.ad_region_mapping[var.region]
}

resource "oci_core_virtual_network" "test_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "testVCN"
  dns_label      = "testvcn"
}

resource "oci_core_subnet" "test_subnet" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "testSubnet"
  dns_label         = "testsubnet"
  security_list_ids = [oci_core_security_list.test_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.test_vcn.id
  route_table_id    = oci_core_route_table.test_route_table.id
  dhcp_options_id   = oci_core_virtual_network.test_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "test_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "testIG"
  vcn_id         = oci_core_virtual_network.test_vcn.id
}

resource "oci_core_route_table" "test_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.test_vcn.id
  display_name   = "testRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

resource "oci_core_security_list" "test_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.test_vcn.id
  display_name   = "testSecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "3000"
      min = "3000"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "3005"
      min = "3005"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "80"
      min = "80"
    }
  }
}

resource "oci_core_instance" "free_instance" {
  count = 2
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "Server${format("%d", count.index)}"
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.test_subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "freeinstance${format("%d", count.index)}"
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

}

# sleep
resource "null_resource" "delay" {
  provisioner "local-exec" {
    command = "sleep 200m"
  }
}

# remote execution
resource "null_resource" "remote-exec-setup" {
   count = 2
  connection {
    host              = element(oci_core_instance.free_instance.*.public_ip, count.index)
    user              = "opc"
    type              = "ssh"
    private_key       = file("~/keys/ServerKey")
    timeout           = "2m"
  }

  provisioner "file" {
    source      = "~/keys/ServerKey"
    destination = "~/.ssh/ServerKey.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "echo -e 'Host Server\n\tHostName ${element(oci_core_instance.free_instance.*.public_ip, count.index == 0 ? 1 : 0)}\n\tUser opc\n\tPort 22\n\tIdentityFile ~/.ssh/ServerKey.pem'  > ~/.ssh/config",
      "chmod 600 ~/.ssh/config",
      "chmod 400 ~/.ssh/ServerKey.pem"
    ]
  }

  provisioner "local-exec" {
    command = "echo 'Host ${element(oci_core_instance.free_instance[*].display_name, count.index )}\n\tHostName ${element(oci_core_instance.free_instance.*.public_ip, count.index)}\n\tUser opc\n\tPort 22\n\tIdentityFile ~/.ssh/ServerKey'  >> ~/.ssh/config"
  }

  depends_on = [
    oci_core_instance.free_instance,null_resource.delay
  ]

}


# load balancer
#
#resource "oci_load_balancer" "free_load_balancer" {
#  #Required
#  compartment_id = var.compartment_ocid
#  display_name   = "alwaysFreeLoadBalancer"
#  shape          = "10Mbps"
#
#  subnet_ids = [
#    oci_core_subnet.test_subnet.id,
#  ]
#}
#
#resource "oci_load_balancer_backend_set" "free_load_balancer_backend_set" {
#  name             = "lbBackendSet1"
#  load_balancer_id = oci_load_balancer.free_load_balancer.id
#  policy           = "ROUND_ROBIN"
#
#  health_checker {
#    port                = "80"
#    protocol            = "HTTP"
#    response_body_regex = ".*"
#    url_path            = "/"
#  }
#
#  session_persistence_configuration {
#    cookie_name      = "lb-session1"
#    disable_fallback = true
#  }
#}
#
#resource "oci_load_balancer_backend" "free_load_balancer_test_backend0" {
#  #Required
#  backendset_name  = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
#  ip_address       = oci_core_instance.free_instance.0.public_ip
#  load_balancer_id = oci_load_balancer.free_load_balancer.id
#  port             = "80"
#}
#
#resource "oci_load_balancer_backend" "free_load_balancer_test_backend1" {
#  #Required
#  backendset_name  = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
#  ip_address       = oci_core_instance.free_instance.1.public_ip
#  load_balancer_id = oci_load_balancer.free_load_balancer.id
#  port             = "80"
#}
#
#resource "oci_load_balancer_hostname" "test_hostname1" {
#  #Required
#  hostname         = "chaitu.org"
#  load_balancer_id = oci_load_balancer.free_load_balancer.id
#  name             = "hostname1"
#}
#
#resource "oci_load_balancer_listener" "load_balancer_listener0" {
#  load_balancer_id         = oci_load_balancer.free_load_balancer.id
#  name                     = "http"
#  default_backend_set_name = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
#  hostname_names           = [oci_load_balancer_hostname.test_hostname1.name]
#  port                     = 80
#  protocol                 = "HTTP"
#  rule_set_names           = [oci_load_balancer_rule_set.test_rule_set.name]
#
#  connection_configuration {
#    idle_timeout_in_seconds = "240"
#  }
#}
#
#resource "oci_load_balancer_rule_set" "test_rule_set" {
#  items {
#    action = "ADD_HTTP_REQUEST_HEADER"
#    header = "example_header_name"
#    value  = "example_header_value"
#  }
#
#  items {
#    action          = "CONTROL_ACCESS_USING_HTTP_METHODS"
#    allowed_methods = ["GET", "POST"]
#    status_code     = "405"
#  }
#
#  load_balancer_id = oci_load_balancer.free_load_balancer.id
#  name             = "test_rule_set_name"
#}
#
#resource "oci_load_balancer_certificate" "load_balancer_certificate" {
#  load_balancer_id   = oci_load_balancer.free_load_balancer.id
#  ca_certificate     =   "-----BEGIN CERTIFICATE-----\nMIIEFTCCAv2gAwIBAgIUCmel8MoxgjkDGLkUw0EYDCKBno8wDQYJKoZIhvcNAQEL\nBQAwgagxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQH\nEw1TYW4gRnJhbmNpc2NvMRkwFwYDVQQKExBDbG91ZGZsYXJlLCBJbmMuMRswGQYD\nVQQLExJ3d3cuY2xvdWRmbGFyZS5jb20xNDAyBgNVBAMTK01hbmFnZWQgQ0EgMjk4\nMTk1YjQ1MTY3MWE5YTYyN2FiMzBlNzExNjM1OGEwHhcNMjExMjAzMTQxODAwWhcN\nMzYxMTI5MTQxODAwWjAiMQswCQYDVQQGEwJVUzETMBEGA1UEAxMKQ2xvdWRmbGFy\nZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALDh3daGZWvEWdTwFYkN\nFqoehUbetFJMNCmI4UBDv6lyGmtcIYPDS9hRoFknrB5yk6bHSKEyIPn23vUrTSnc\nQIt3qVYARZPI2j4R+P/xg6S9vglC3sggwzyqrrwNqCqkZiP5AIcG+4c71ZRAJBfo\n47ZQwBg0QZupSfOjxamvwOS2OsPumvlNNK3JtjsGTz2MLwyHv7kI4/oILQyGGAuv\n6GpiD6VGEc2SGE2h8Prv8n9BsFOerfD29RazNvj7G1gFeEx6ZM98M7GoyOLnKspj\nCcaQfHHgbUI3MIDotv4YCUpkXnuo92ZXool8MEWDXhNCyVQ1R0BxObVC/DThMkKe\njjcCAwEAAaOBuzCBuDATBgNVHSUEDDAKBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAA\nMB0GA1UdDgQWBBRW8nvA3y+SmzPs1yzwDj44cT404DAfBgNVHSMEGDAWgBTUMdAM\nDBkK0p25txFwkjyco8J1wDBTBgNVHR8ETDBKMEigRqBEhkJodHRwOi8vY3JsLmNs\nb3VkZmxhcmUuY29tLzA4NjU5NWMyLWU2ODEtNDI5OS05MjRhLWM3MjU4NWJjZWZj\nMC5jcmwwDQYJKoZIhvcNAQELBQADggEBAKmgh8729MxMSpQoVJdIqeICahFAwI0L\nOyVlT0u3G6GCgc7ikXhrwpeg4be0hGQSBOH4Wan78ehqrgkwKKM1HAVnUE/ej73+\nM4O0CuZ7ZMvcgvwzG6hjJ56hrK0e1+0CQf9w9pFs5YKYZyEmrRlgPtoPkOYvc0BO\n47cMxKI0/KQn8dUlZC9kmZJO05DLrrh6CDY+UdqE/dTD9G01NyjVEwcG0egE5TXD\nUY1KhevGl3euJDTuWPTSUB94suoi3CdV0jyOxXZXGdyeQGxzbzdKwE2c9sIQHHZK\nJNJCo/zSGtIfRyNM2ZS592y8BHnmqjh/dTyNpLVb3CiT9SQ6C5AxhDw=\n-----END CERTIFICATE-----"
#  certificate_name   = "certificate1"
#  private_key        = "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCw4d3WhmVrxFnU\n8BWJDRaqHoVG3rRSTDQpiOFAQ7+pchprXCGDw0vYUaBZJ6wecpOmx0ihMiD59t71\nK00p3ECLd6lWAEWTyNo+Efj/8YOkvb4JQt7IIMM8qq68DagqpGYj+QCHBvuHO9WU\nQCQX6OO2UMAYNEGbqUnzo8Wpr8DktjrD7pr5TTStybY7Bk89jC8Mh7+5COP6CC0M\nhhgLr+hqYg+lRhHNkhhNofD67/J/QbBTnq3w9vUWszb4+xtYBXhMemTPfDOxqMji\n5yrKYwnGkHxx4G1CNzCA6Lb+GAlKZF57qPdmV6KJfDBFg14TQslUNUdAcTm1Qvw0\n4TJCno43AgMBAAECggEASWGCy09ZPxKn4++wN3nPF8duqj6VF3lWwI5xSFxy5ISa\nUkTYAJZiXj1K5QHQ5ZbKC4wsZPdrd9gDmjmbGw0tV87OWQfm1Y8jf1Gsd94Fq7At\n6SCtVOBGruHueMS/qeUnHLBeGCZ87hcUHZtYffTXl1i7wK7ZMw9Rxzp/s8xenWMM\nsaTd2+FsGrHhcJ73pYwo0jiPOp9KVbC6t1cgIS6KRC+RLQxKzwsMdmwJWn1QuLXe\naFX3DFSnfNFXBuqpNxS9jscTKF5GL36TFcM+mmykczABAjPkuiFh9v6d1pQehyvk\nMKiK1NBLDc3eDoB5YYTb8iIiHM3BJPwPX1cAhqFJTQKBgQDtb7KsRtePu2xJQJEu\ngppe9lDxbhz23EmFIeoGVLvw6Zb49zZF1rB2VQuse4uaOPE8ntDC254tIw25hWP+\nB2XDn5Gy3OB+Qg4QUJdWbrL0W17Elh9RIteV6q127vSrWyM638q3gS+2JCRzAl9p\n4txQ8VYWIfn7RVbm297hqrQi0wKBgQC+ti0WpVJqWy0sZoN0wsyUWrqYAll7ydhb\nabDUyYTtaq1jTxNyWgCVCyLRimDpKfZtSs7MvQU/DAyJlM/d3o6l2G/MK8uf/TNb\n4AMdsiBzzcNszbYwMSY7mhm9vRlinvLEuKGOSFcaLdQHSQ7V4AjdLCRfKtR10+kp\nQOa1iJ8gjQKBgHkPdZM/P5NqZWjoAd4r+xemEVk34o6/fMDjrNXziCvqfe6M5WAw\neaKr9BrKl0BX/jABbcGchobPE6Ve7L/N98YJaxk+Yzwc49zPqooIQTg0ChrDzE3r\nLO6kTDOS3K8t9cWD63Eq7i+5N9hoAkwTvm+KzXDVfAbwsMFeo8J97gC/AoGAVsCg\nOhDyMJdRMUVgvxht3352KvfGpNzoooytd95DrYw9W1N5USdH5ISwTglYlDgWdRj2\ngYPqgweEHIGpHRBEa4TNNl8lvZ18Y2q/gB6rTIJpR3E8UyfIcIxk8T638XjEjmA+\nfW7C0JHQRZAiQ4AqCBIwaWoeQ4smITH4wNNpL3ECgYEA0g602mLyOTFu4tTD+lBW\nRz8U3bkMHzT7QdMQgdnRRsKaMnMrqvY7fAKAn7q2w6ycJLqkJYh9oHzqGOJrdzg3\nO5T2Gcz8BxDsz8jkSWMt2kEV16v9nXI7HSt3vWBijzWWoJrR8pv56JciVQP2QGOz\np/FX/j6/7pHb1Iy/jCGKFWo=\n-----END PRIVATE KEY-----"
#  public_certificate = "-----BEGIN CERTIFICATE-----\nMIIEFTCCAv2gAwIBAgIUCmel8MoxgjkDGLkUw0EYDCKBno8wDQYJKoZIhvcNAQEL\nBQAwgagxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpDYWxpZm9ybmlhMRYwFAYDVQQH\nEw1TYW4gRnJhbmNpc2NvMRkwFwYDVQQKExBDbG91ZGZsYXJlLCBJbmMuMRswGQYD\nVQQLExJ3d3cuY2xvdWRmbGFyZS5jb20xNDAyBgNVBAMTK01hbmFnZWQgQ0EgMjk4\nMTk1YjQ1MTY3MWE5YTYyN2FiMzBlNzExNjM1OGEwHhcNMjExMjAzMTQxODAwWhcN\nMzYxMTI5MTQxODAwWjAiMQswCQYDVQQGEwJVUzETMBEGA1UEAxMKQ2xvdWRmbGFy\nZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALDh3daGZWvEWdTwFYkN\nFqoehUbetFJMNCmI4UBDv6lyGmtcIYPDS9hRoFknrB5yk6bHSKEyIPn23vUrTSnc\nQIt3qVYARZPI2j4R+P/xg6S9vglC3sggwzyqrrwNqCqkZiP5AIcG+4c71ZRAJBfo\n47ZQwBg0QZupSfOjxamvwOS2OsPumvlNNK3JtjsGTz2MLwyHv7kI4/oILQyGGAuv\n6GpiD6VGEc2SGE2h8Prv8n9BsFOerfD29RazNvj7G1gFeEx6ZM98M7GoyOLnKspj\nCcaQfHHgbUI3MIDotv4YCUpkXnuo92ZXool8MEWDXhNCyVQ1R0BxObVC/DThMkKe\njjcCAwEAAaOBuzCBuDATBgNVHSUEDDAKBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAA\nMB0GA1UdDgQWBBRW8nvA3y+SmzPs1yzwDj44cT404DAfBgNVHSMEGDAWgBTUMdAM\nDBkK0p25txFwkjyco8J1wDBTBgNVHR8ETDBKMEigRqBEhkJodHRwOi8vY3JsLmNs\nb3VkZmxhcmUuY29tLzA4NjU5NWMyLWU2ODEtNDI5OS05MjRhLWM3MjU4NWJjZWZj\nMC5jcmwwDQYJKoZIhvcNAQELBQADggEBAKmgh8729MxMSpQoVJdIqeICahFAwI0L\nOyVlT0u3G6GCgc7ikXhrwpeg4be0hGQSBOH4Wan78ehqrgkwKKM1HAVnUE/ej73+\nM4O0CuZ7ZMvcgvwzG6hjJ56hrK0e1+0CQf9w9pFs5YKYZyEmrRlgPtoPkOYvc0BO\n47cMxKI0/KQn8dUlZC9kmZJO05DLrrh6CDY+UdqE/dTD9G01NyjVEwcG0egE5TXD\nUY1KhevGl3euJDTuWPTSUB94suoi3CdV0jyOxXZXGdyeQGxzbzdKwE2c9sIQHHZK\nJNJCo/zSGtIfRyNM2ZS592y8BHnmqjh/dTyNpLVb3CiT9SQ6C5AxhDw=\n-----END CERTIFICATE-----"
#
#  lifecycle {
#    create_before_destroy = true
#  }
#}
#
#resource "oci_load_balancer_listener" "load_balancer_listener1" {
#  load_balancer_id         = oci_load_balancer.free_load_balancer.id
#  name                     = "https"
#  default_backend_set_name = oci_load_balancer_backend_set.free_load_balancer_backend_set.name
#  port                     = 443
#  protocol                 = "HTTP"
#
#  ssl_configuration {
#    certificate_name        = oci_load_balancer_certificate.load_balancer_certificate.certificate_name
#    verify_peer_certificate = false
#  }
#}