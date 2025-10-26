// deploy/deploy.ts
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const WAIT = parseInt(process.env.WAIT_CONFIRMS ?? "1");

  const result = await deploy("AnonymousTeacherRating", {
    from: deployer,
    args: [],               // <── КЛЮЧЕВОЕ
    log: true,
    waitConfirmations: WAIT,
  });

  // опционально: пост-инициализация
  // const c = await hre.ethers.getContractAt("AnonymousTeacherRating", result.address);
  // for (let id = 1; id <= Number(process.env.TEACHERS_COUNT ?? 0); id++) {
  //   await (await c.addTeacher(id, `Teacher #${id}`)).wait(WAIT);
  // }
};

export default func;
func.tags = ["AnonymousTeacherRating"];
