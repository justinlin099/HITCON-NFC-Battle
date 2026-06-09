import { SCORE_PER_COLLECTION } from "./game-config";

export function calculateScore(numOfCollection: number) {
  return SCORE_PER_COLLECTION * numOfCollection;
}
