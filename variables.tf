variable "tenancy_ocid" {
}

variable "user_ocid" {
}

variable "fingerprint" {
}

variable "private_key_path" {
}

variable "ssh_public_key" {

}

variable "compartment_ocid" {
}

variable "region" {
}

variable "ad_region_mapping" {
type = map(string)

default = {
  ap-hyderabad-1 = 1
  }
}

variable "images" {
type = map(string)

default = {
  # See https://docs.us-phoenix-1.oraclecloud.com/images/
  # Oracle-provided image "Oracle-Linux-7.5-2018.10.16-0"
  ap-hyderabad-1 = "ocid1.image.oc1.ap-hyderabad-1.aaaaaaaaymi2dhsj2724wvors2i42x6fwazvlp4pcmclvweidb2cokhtiw4q"
  }
}