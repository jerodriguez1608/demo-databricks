terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    databricks = {
      source = "databricks/databricks"
      version = "1.37.1"
    }
  }
}

variable "databricks_host" {}
variable "databricks_token" {}

locals {
  libraries = yamldecode(file("${path.module}/libraries.yaml"))
  workflow  = yamldecode(file("${path.module}/workflow.yaml"))
  templates  = yamldecode(file("${path.module}/templates.yaml"))
  cluster_configs = yamldecode(file("${path.module}/cluster-configs.yaml"))["dev"] 
  workflow_configs  = yamldecode(file("${path.module}/workflow-configs.yaml"))["dev"] 
}


provider "azurerm" {
  features {}
}

# Use environment variables for authentication.
provider "databricks" {
  host  = var.databricks_host #${{secrets.DATABRICKS_URL_DEPLOY}} #"adb-144988797342511.11.azuredatabricks.net"
  token = var.databricks_token #${{secrets.DATABRICKS_TOKEN_DEPLOY}} #"dapie6921f56ad129e9caacfe99d429ac40f-3"
  
}

#resource "databricks_group" "auto" {
  #display_name = "Automation"
#}

#resource "databricks_group" "eng" {
  #display_name = "Engineering"
#}

data "databricks_spark_version" "latest" {}


locals {

 conectores = keys(local.templates)

}


resource "databricks_job" "this" {

  run_as {
    user_name =  local.workflow.dataengineer
  }

  name = local.workflow.workflow
  max_concurrent_runs = 1

  #git_source {
    #url = ""
    #branch = ""
    #provider = ""
  #}

  
  # dynamic "schedule" {
  #   for_each =  [for k, data in [local.workflow.schedule]: data if  data != "continuous"] 
  #   content {
  #     quartz_cron_expression = data
  #     timezone_id            = "America/Bogota"
  #     pause_status           = "UNPAUSED"
  #   }
    
  # }

  # dynamic "continuous" {
  #   for_each =   [for k, data in [local.workflow.schedule]: data if  data == "continuous"] 
  #   content {
  #     pause_status = "PAUSED"
  #   }
  # }


  dynamic "task" {

    for_each = { for k, bd in local.workflow.tasks : k => bd }



    content {
      task_key = task.key

      max_retries = 0

      job_cluster_key = task.value.cluster-name



      notebook_task {
        
        notebook_path = lookup ( local.templates , task.value.apply , task.value.apply) 
        
        base_parameters =  task.value.params
     
      }

      dynamic "library" {
        
        for_each = setunion(
                flatten([ for key, elem in  local.libraries :  
                                                    flatten( 
                                                      values(
                                                        {for k, e in  elem : k => e })) if contains(task.value.libraries.repository, key) ] ) ,
               [ for k, v in  (contains(keys(task.value.libraries), "maven") ?  task.value.libraries.maven : [] )  : v ] ,
               [ for k, v in  (contains(keys(task.value.libraries), "dbfs") ?  task.value.libraries.dbfs : [] )  : v ]

        )
        content {
 
          dynamic "maven" {
            for_each = [for v  in  [library.value] : library.value if !(length(regexall("dbfs.*", library.value)) > 0) ]
            content {
              coordinates =  library.value
            }
          }
          
          jar =  length(regexall("dbfs.*", library.value)) > 0 ? library.value :  ""   

         }

      }


      dynamic "depends_on" {
        for_each =  {for k, e in  contains(keys(task.value), "depends") ? task.value.depends  : [] :  k => e if e != null} 
        content {
          task_key = depends_on.value
        }
      }

      
    }

  }


  ##mejorar
  dynamic "job_cluster" {

    for_each = { for k, data in local.workflow.clusters : k => data }

    content {
      job_cluster_key = job_cluster.key
      new_cluster {
        custom_tags = merge(
          {
            "ResourceClass" : "SingleNode",
            "pip-yape-users" : local.workflow.workflow
          }, 
          local.cluster_configs.tags,
          job_cluster.value.tags
        )
        
        num_workers   = 0
        spark_version = data.databricks_spark_version.latest.id
        # policy_id     = local.cluster_configs.policyId # "C96178C1CF00011D"

        spark_conf = local.cluster_configs.configs

        driver_node_type_id = job_cluster.value.size
        
        node_type_id = job_cluster.value.size
      }
    }
  }

  email_notifications {
    on_success = ["jhonerodriguez@bcp.com.pe"]
    on_failure = ["jhonerodriguez@bcp.com.pe"]
  }


}


# resource "databricks_permissions" "job_usage" {
#   job_id = databricks_job.this.id

#   dynamic "access_control" {
#     content {
#        group_name       = "users"
#        permission_level = "CAN_VIEW"
#     }
#   }
#   access_control {
#     group_name       = "users"
#     permission_level = "CAN_VIEW"
#   }

#   access_control {
#     group_name       = databricks_group.auto.display_name
#     permission_level = "CAN_MANAGE_RUN"
#   }

#   access_control {
#     group_name       = databricks_group.eng.display_name
#     permission_level = "CAN_MANAGE"
#   }
# }

output "job_url" {
  value = databricks_job.this.url
}


