# IAM user + policy used by the fleeting-plugin-aws running inside the
# runner manager container. Scoped to just this ASG's autoscaling actions
# plus read-only EC2 describe (needed to resolve instance addresses).

resource "aws_iam_user" "runner" {
  name = "${var.name_prefix}-fleeting"
  path = "/gitlab-runner/"
}

resource "aws_iam_access_key" "runner" {
  user = aws_iam_user.runner.name
}

data "aws_iam_policy_document" "runner" {
  statement {
    sid    = "AutoscalingManage"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = [aws_autoscaling_group.runner.arn]
  }

  statement {
    sid    = "AutoscalingDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeScalingActivities",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "Ec2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_user_policy" "runner" {
  name   = "${var.name_prefix}-fleeting-policy"
  user   = aws_iam_user.runner.name
  policy = data.aws_iam_policy_document.runner.json
}
