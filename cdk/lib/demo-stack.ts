import * as cdk from 'aws-cdk-lib';
import {
  aws_autoscaling as autoscaling,
  aws_cloudwatch as cloudwatch,
  aws_ec2 as ec2,
  aws_elasticloadbalancingv2 as elbv2,
} from 'aws-cdk-lib';
import { Construct } from 'constructs';

const AMI_ID = 'ami-06174c8686ce68c26';
const INSTANCE_TYPE = 't2.micro';

const DEFAULT_ALB_INGRESS_CIDR = '203.0.113.0/24';

// us-east-1e (and the other default AZs) are capacity-constrained in this
// account, so pin the ALB and ASG to us-east-1a and us-east-1b.
const PUBLIC_SUBNETS: ec2.SubnetSelection = {
  subnetType: ec2.SubnetType.PUBLIC,
  availabilityZones: ['us-east-1a', 'us-east-1b'],
};

export class DemoStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const albIngressCidr: string =
      this.node.tryGetContext('albIngressCidr') ?? DEFAULT_ALB_INGRESS_CIDR;

    cdk.Tags.of(this).add('Project', 'iac-demo');
    cdk.Tags.of(this).add('ProvisionedBy', 'cdk');

    // Default VPC and its subnets, discovered at deploy time.
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // 1. ALB security group: inbound HTTP from the deploying host.
    const albSg = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc,
      securityGroupName: 'cdk-alb-sg',
      description: 'cdk ALB - inbound HTTP from the deploying host',
      allowAllOutbound: true,
    });
    albSg.addIngressRule(ec2.Peer.ipv4(albIngressCidr), ec2.Port.tcp(80), 'HTTP from deploying host');

    // 2. Instance security group: inbound HTTP from the ALB security group.
    const ec2Sg = new ec2.SecurityGroup(this, 'Ec2Sg', {
      vpc,
      securityGroupName: 'cdk-ec2-sg',
      description: 'cdk EC2 - inbound HTTP from the ALB security group',
      allowAllOutbound: true,
    });
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(80), 'HTTP from ALB security group');

    // 3. Launch template.
    const lt = new ec2.LaunchTemplate(this, 'Lt', {
      launchTemplateName: 'cdk-lt',
      machineImage: ec2.MachineImage.genericLinux({ 'us-east-1': AMI_ID }),
      instanceType: new ec2.InstanceType(INSTANCE_TYPE),
      securityGroup: ec2Sg,
    });

    // 4. Auto scaling group (1-3 instances, ELB health checks).
    const asg = new autoscaling.AutoScalingGroup(this, 'Asg', {
      autoScalingGroupName: 'cdk-asg',
      launchTemplate: lt,
      vpc,
      vpcSubnets: PUBLIC_SUBNETS,
      minCapacity: 1,
      maxCapacity: 3,
      desiredCapacity: 1,
      healthCheck: autoscaling.HealthCheck.elb({ grace: cdk.Duration.seconds(300) }),
    });

    // 5. Internet-facing Application Load Balancer.
    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      loadBalancerName: 'cdk-alb',
      vpc,
      internetFacing: true,
      vpcSubnets: PUBLIC_SUBNETS,
      securityGroup: albSg,
    });

    // 6. Target group; registering the ASG attaches it to the group.
    const tg = new elbv2.ApplicationTargetGroup(this, 'Tg', {
      targetGroupName: 'cdk-tg',
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        path: '/health.php',
        port: '80',
        protocol: elbv2.Protocol.HTTP,
        healthyHttpCodes: '200',
      },
      targets: [asg],
    });

    // 7. HTTP listener. open:false keeps the ALB security group ingress to the host /32.
    alb.addListener('Http', {
      port: 80,
      defaultTargetGroups: [tg],
      open: false,
    });

    // 8-11. Step scaling: +1 above 40% CPU, -1 at or below 10%.
    // scaleOnMetric builds the two policies and their alarms.
    asg.scaleOnMetric('CpuScaling', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        dimensionsMap: { AutoScalingGroupName: asg.autoScalingGroupName },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      scalingSteps: [
        { upper: 10, change: -1 },
        { lower: 40, change: 1 },
      ],
      adjustmentType: autoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      estimatedInstanceWarmup: cdk.Duration.seconds(300),
      evaluationPeriods: 1,
      datapointsToAlarm: 1,
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      description: 'Public DNS name of the ALB',
      value: alb.loadBalancerDnsName,
    });
    new cdk.CfnOutput(this, 'TargetGroupArn', {
      description: 'ARN of the target group',
      value: tg.targetGroupArn,
    });
    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      description: 'Name of the auto scaling group',
      value: asg.autoScalingGroupName,
    });
  }
}
