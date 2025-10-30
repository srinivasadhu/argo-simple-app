# 🔧 (Optional) Improvements You Can Apply

The following improvements enhance flexibility, ensure multi-port handling works correctly, and make your module fully reusable across multiple scenarios.

---

### **1️⃣ Multi-port expansion**  
> *(Current code only uses `ports[0]` — this fixes it to create one rule per port)*

Replace your existing `cidr_multi_port_rules` ingress block in `main.tf` with:

```hcl
dynamic "ingress" {
  for_each = {
    for rule in var.cidr_multi_port_rules :
    # create one key per (rule,port) pair to ensure unique map keys
    for p in rule.ports : "${rule.cidr}-${p}" => {
      cidr        = rule.cidr
      port        = p
      protocol    = rule.protocol
      description = try(rule.description, null)
    }
  }
  content {
    description = ingress.value.description
    from_port   = ingress.value.port
    to_port     = ingress.value.port
    protocol    = ingress.value.protocol
    cidr_blocks = [ingress.value.cidr]
  }
}
```

✅ **Why:** This generates *one ingress rule per port*, avoiding the limitation of only opening the first port in each list.

---

### **2️⃣ Range rules**

Add or update your block for CIDR-based port ranges:

```hcl
dynamic "ingress" {
  for_each = { for i, r in var.cidr_range_rules : i => r }
  content {
    description = try(ingress.value.description, null)
    from_port   = ingress.value.from_port
    to_port     = ingress.value.to_port
    protocol    = ingress.value.protocol
    cidr_blocks = [ingress.value.cidr]
  }
}
```

✅ **Why:** This supports continuous port ranges (e.g., 8000–9000) for services requiring multiple ports under a single rule.

---

### **3️⃣ SG → SG per-port expansion**

Use this for Security Group–to–Security Group references, ensuring multiple ports are handled properly:

```hcl
dynamic "ingress" {
  for_each = {
    for rule in var.sg_source_rules :
    for p in rule.ports : "${rule.source_sg_id}-${p}" => {
      source_sg_id = rule.source_sg_id
      port         = p
      protocol     = rule.protocol
      description  = try(rule.description, null)
    }
  }
  content {
    description     = ingress.value.description
    from_port       = ingress.value.port
    to_port         = ingress.value.port
    protocol        = ingress.value.protocol
    security_groups = [ingress.value.source_sg_id]
  }
}
```

✅ **Why:** Expands SG → SG rules dynamically per port, giving you fine-grained control between modules (e.g., app → db).

---

### **4️⃣ Conditional egress honoring `allow_all_egress`**

To make the `allow_all_egress` variable effective, use this pattern:

```hcl
dynamic "egress" {
  for_each = var.allow_all_egress ? [1] : []
  content {
    from_port         = 0
    to_port           = 0
    protocol          = "-1"
    cidr_blocks       = ["0.0.0.0/0"]
    ipv6_cidr_blocks  = ["::/0"]
    description       = "Allow all egress"
  }
}
```

✅ **Why:**  
- If `allow_all_egress = true`, allows all outbound traffic.  
- If set to `false`, the block won’t be created — enabling restricted outbound policies.

---

### 🧩 **Summary**

| Improvement | Purpose |
|--------------|----------|
| **Multi-port expansion** | Creates one rule per port, not just the first |
| **Range rules** | Adds flexible continuous port ranges |
| **SG → SG expansion** | Enables per-port control between SGs |
| **Conditional egress** | Makes outbound access configurable |

---

🟩 **Benefit:**  
With these refinements, your module now fully supports **multi-scenario dynamic rule generation**, making it suitable for enterprise-grade use in ALB, EKS, and wrapper orchestration modules.

---

## 🚀 Example Usage After Improvements

### **Example 1: Web Application SG (Public Ingress)**

```hcl
module "sg_web" {
  source = "../ns-security-group"
  name   = "web-sg"
  vpc_id = "vpc-0123456789abcdef"

  cidr_multi_port_rules = [
    {
      cidr        = "0.0.0.0/0"
      ports       = [80, 443]
      protocol    = "tcp"
      description = "Allow public web access"
    }
  ]

  allow_all_egress = true
  tags = {
    Environment = "dev"
    Owner       = "Srini"
  }
}
```

### **Example 2: Application-to-Database SG (SG→SG Reference)**

```hcl
module "sg_app" {
  source = "../ns-security-group"
  name   = "app-sg"
  vpc_id = "vpc-0123456789abcdef"
}

module "sg_db" {
  source = "../ns-security-group"
  name   = "db-sg"
  vpc_id = "vpc-0123456789abcdef"

  sg_source_rules = [
    {
      source_sg_id = module.sg_app.id
      ports        = [3306]
      protocol     = "tcp"
      description  = "Allow App to connect to DB"
    }
  ]
}
```

### **Example 3: CIDR Range Rule (Multiple Ports Together)**

```hcl
module "sg_backend" {
  source = "../ns-security-group"
  name   = "backend-sg"
  vpc_id = "vpc-0123456789abcdef"

  cidr_range_rules = [
    {
      cidr        = "10.0.0.0/8"
      from_port   = 8000
      to_port     = 9000
      protocol    = "tcp"
      description = "Allow backend services range"
    }
  ]
}
```

### **Example 4: Integration with ALB**

```hcl
module "sg_alb" {
  source = "../ns-security-group"
  name   = "alb-sg"
  vpc_id = var.vpc_id

  cidr_multi_port_rules = [
    {
      cidr        = "0.0.0.0/0"
      ports       = [80, 443]
      protocol    = "tcp"
      description = "Allow public web traffic"
    }
  ]
}

module "alb" {
  source              = "../alb-module"
  name                = "ns-app-alb"
  vpc_id              = var.vpc_id
  subnets             = var.public_subnets
  security_group_ids  = [module.sg_alb.id]
}
```

### ✅ **How to Test**

```bash
cd examples/basic
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -auto-approve -var-file="terraform.tfvars"
terraform destroy -auto-approve -var-file="terraform.tfvars"
```
