// Databricks notebook source
var branch = dbutils.widgets.get("branch")
var environment = dbutils.widgets.get("environment")
println(s"${branch} -- ${environment}")
