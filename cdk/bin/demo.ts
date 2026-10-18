import * as cdk from 'aws-cdk-lib';
import { DemoStack } from '../lib/demo-stack';

const app = new cdk.App();

new DemoStack(app, 'cdk-autoscaling', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // No bootstrap, no IAM roles: deploys with the CLI's own credentials.
  synthesizer: new cdk.LegacyStackSynthesizer(),
});
