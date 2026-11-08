const { ethers } = require("hardhat");
async function main() {
    const c = await ethers.deployContract("VolunteerHoursTracker");
    await c.waitForDeployment();
    console.log("Deployed to", await c.getAddress());
}
main().catch((e) => {
    console.error(e);
    process.exit(1);
});
