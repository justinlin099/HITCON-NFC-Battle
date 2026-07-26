import { PHISHING_PENALTY, SCORE_PER_COLLECTION } from "./game-config";

export function calculateScore(numOfCollection: number, numOfPhishing: number) {
  return (SCORE_PER_COLLECTION * numOfCollection) - (PHISHING_PENALTY * numOfPhishing);
}
