variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "minecraft_course_project_2"
}

variable "volume_size" {
  description = "Size of the created EC2 instance volume in GiB"
  type        = int
  default     = 9
}

variable "instance_type" {
  description = "What resources we want to give to the instance"
  type        = string
  default     = "acme-minecraft"
}

