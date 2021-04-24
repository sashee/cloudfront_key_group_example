const { SSMClient, GetParameterCommand } = require("@aws-sdk/client-ssm");
const cfUtil = require('aws-cloudfront-sign');

const ssm = new SSMClient();

const cacheSsmGetParameter = (params, cacheTime) => {
	let lastRefreshed = undefined;
	let lastResult = undefined;
	let queue = Promise.resolve();
	return () => {
		const res = queue.then(async () => {
			const currentTime = new Date().getTime();
			if (lastResult === undefined || lastRefreshed + cacheTime < currentTime) {

				lastResult = await ssm.send(new GetParameterCommand(params));
				lastRefreshed = currentTime;
			}
			return lastResult;
		});
		queue = res.catch(() => {});
		return res;
	};
};

const getPrivateKey = cacheSsmGetParameter({Name: process.env.PRIVATE_KEY_PARAMETER, WithDecryption: true}, 15 * 1000);

const cfKeyPairId = process.env.KEYPAIR_ID;
const cfDomain = process.env.CLOUDFRONT_DOMAIN;

module.exports.handler = async (event) => {
	const cfPk = (await getPrivateKey()).Parameter.Value;
	console.log(cfPk);
	const cfURL = `https://${cfDomain}/secret.txt`;

	const signedUrl = cfUtil.getSignedUrl(cfURL, {
		keypairId: cfKeyPairId,
		expireTime: Date.now() + 60000,
		privateKeyString: cfPk
	});
	return {
		statusCode: 303,
		headers: {
			Location: signedUrl,
		}
	};
};

