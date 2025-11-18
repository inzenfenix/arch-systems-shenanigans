module "ec2" {
  source = "./ec2"

  vpc_id = module.vpc.vpc_id
  private_eks_subnet_ids = module.vpc.private_backends_subnet_id
  private_db_subnet_id =  module.vpc.private_db_subnet_id
}

module "vpc" {
  source = "./vpc"
}