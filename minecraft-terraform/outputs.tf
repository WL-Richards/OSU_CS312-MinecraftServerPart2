
# Output the public IP address of our server so we can connect to it
#--------------------------------------------------------------------------------
output "public_ip" {
  value = aws_instance.minecraft.public_ip
}
#--------------------------------------------------------------------------------