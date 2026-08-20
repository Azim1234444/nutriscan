/**
 * Security rule tests for `users/{uid}/meals/{mealId}`.
 *
 * These run against the Firestore emulator, so they only execute when it is
 * running. Start it first:
 *
 *   firebase emulators:start --only firestore --project nutriscan-a66ae
 *   npm --prefix functions run test:rules
 */

import { readFileSync } from "fs";
import { resolve } from "path";

import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

/**
 * Where the emulator is listening, as the emulator itself reported it.
 *
 * No fallback on purpose: `test/require-emulator.ts` has already refused the
 * run if this is missing, so there is no port written down here to fall out of
 * step with firebase.json.
 */
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST ?? "";
const [host, port] = emulatorHost.split(":");

/** A meal document that satisfies the rules. */
function validMeal(userId: string) {
  const nutrition = {
    foodName: "Grilled chicken salad",
    description: "Mixed leaves with chicken.",
    estimatedPortionGrams: 320,
    calories: 580,
    proteinGrams: 42,
    carbohydratesGrams: 18,
    fatGrams: 24,
    fiberGrams: 6,
  };

  return {
    userId,
    foodName: nutrition.foodName,
    description: nutrition.description,
    mealType: "lunch",
    estimatedPortionGrams: nutrition.estimatedPortionGrams,
    aiEstimate: { ...nutrition, confidence: 0.85, assumptions: [], items: [] },
    current: nutrition,
    isEdited: false,
    createdAt: new Date(),
  };
}

// Never skipped. This file is reached only through vitest.rules.config.ts,
// which has already made sure there is an emulator to talk to; the hermetic
// `npm test` run leaves the file out altogether rather than skipping it.
describe("firestore rules", () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "nutriscan-rules-test",
      firestore: {
        host,
        port: Number(port),
        rules: readFileSync(
          resolve(__dirname, "../../firestore.rules"),
          "utf8",
        ),
      },
    });
  }, 60_000);

  afterAll(async () => {
    await testEnv?.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
  });

  describe("7. one user cannot reach another user's meals", () => {
    beforeEach(async () => {
      // Seed a meal owned by user-b, bypassing the rules.
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .doc("users/user-b/meals/meal-1")
          .set(validMeal("user-b"));
      });
    });

    it("cannot read them", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.doc("users/user-b/meals/meal-1").get());
    });

    it("cannot list them", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.collection("users/user-b/meals").get());
    });

    it("cannot write into them", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-b/meals/meal-2").set(validMeal("user-b")),
      );
    });

    it("cannot overwrite them by claiming their own uid", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-b/meals/meal-1").set(validMeal("user-a")),
      );
    });

    it("cannot delete them", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.doc("users/user-b/meals/meal-1").delete());
    });

    it("but can do all of that with their own meals", async () => {
      const userB = testEnv.authenticatedContext("user-b").firestore();

      await assertSucceeds(userB.doc("users/user-b/meals/meal-1").get());
      await assertSucceeds(userB.collection("users/user-b/meals").get());
      await assertSucceeds(
        userB.doc("users/user-b/meals/meal-3").set(validMeal("user-b")),
      );
      await assertSucceeds(userB.doc("users/user-b/meals/meal-1").delete());
    });
  });

  describe("the weekly range query", () => {
    // Monday 17 August 2026 to the Monday after it: the span the weekly
    // overview asks for. Nothing here needs a new rule - it is the same
    // collection read as a single day - so these prove the existing ones
    // already cover it.
    const weekStart = new Date(2026, 7, 17);
    const weekEnd = new Date(2026, 7, 24);

    type Db = ReturnType<
      ReturnType<RulesTestEnvironment["authenticatedContext"]>["firestore"]
    >;

    function readWeekOf(db: Db, userId: string) {
      return db
        .collection(`users/${userId}/meals`)
        .where("createdAt", ">=", weekStart)
        .where("createdAt", "<", weekEnd)
        .orderBy("createdAt", "desc")
        .get();
    }

    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await db
          .doc("users/user-a/meals/mine")
          .set({ ...validMeal("user-a"), createdAt: new Date(2026, 7, 19, 12) });
        await db
          .doc("users/user-b/meals/theirs")
          .set({ ...validMeal("user-b"), createdAt: new Date(2026, 7, 19, 12) });
      });
    });

    it("lets a user read their own week", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      const meals = await assertSucceeds(readWeekOf(userA, "user-a"));
      expect(meals.docs.map((doc) => doc.id)).toEqual(["mine"]);
    });

    it("does not let a user read another user's week", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(readWeekOf(userA, "user-b"));
    });

    it("rejects the range query without a session", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(readWeekOf(anonymous, "user-a"));
    });
  });

  describe("8. unauthenticated access is rejected", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .doc("users/user-a/meals/meal-1")
          .set(validMeal("user-a"));
      });
    });

    it("cannot read a meal", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(anonymous.doc("users/user-a/meals/meal-1").get());
    });

    it("cannot write a meal", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(
        anonymous.doc("users/user-a/meals/meal-2").set(validMeal("user-a")),
      );
    });

    it("cannot delete a meal", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(anonymous.doc("users/user-a/meals/meal-1").delete());
    });

    it("cannot reach any other collection either", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(anonymous.doc("meals/anything").get());
      await assertFails(anonymous.doc("users/user-a").get());
    });
  });

  describe("meal documents are validated on write", () => {
    it("rejects a meal claiming a different owner", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-a/meals/meal-1").set(validMeal("user-b")),
      );
    });

    it("rejects negative nutrition values", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();
      const meal = validMeal("user-a");
      meal.current.calories = -10;

      await assertFails(userA.doc("users/user-a/meals/meal-1").set(meal));
    });

    it("rejects an empty food name", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();
      const meal = validMeal("user-a");
      meal.current.foodName = "";

      await assertFails(userA.doc("users/user-a/meals/meal-1").set(meal));
    });

    it("rejects a document carrying image data", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();
      const meal = {
        ...validMeal("user-a"),
        imageBase64: "iVBORw0KGgoAAAANSUhEUg",
      };

      await assertFails(userA.doc("users/user-a/meals/meal-1").set(meal));
    });

    it("accepts a well-formed meal", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertSucceeds(
        userA.doc("users/user-a/meals/meal-1").set(validMeal("user-a")),
      );
    });
  });

  describe("meal updates", () => {
    beforeEach(async () => {
      // One meal each, written past the rules so both exist to edit.
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .doc("users/user-a/meals/meal-1")
          .set(validMeal("user-a"));
        await context
          .firestore()
          .doc("users/user-b/meals/meal-1")
          .set(validMeal("user-b"));
      });
    });

    /**
     * The fields the app sends when a meal is edited: the user's values and
     * nothing else. `userId`, `aiEstimate` and `createdAt` are deliberately
     * absent, so the merged document keeps whatever it already had.
     */
    function edit(overrides: Record<string, unknown> = {}) {
      const current = { ...validMeal("user-a").current, calories: 620 };

      return {
        foodName: current.foodName,
        description: current.description,
        mealType: "dinner",
        estimatedPortionGrams: current.estimatedPortionGrams,
        current,
        isEdited: true,
        updatedAt: new Date(),
        ...overrides,
      };
    }

    it("the owner can edit their own meal", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertSucceeds(userA.doc("users/user-a/meals/meal-1").update(edit()));
    });

    it("the owner keeps their meal after editing it", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();
      await assertSucceeds(userA.doc("users/user-a/meals/meal-1").update(edit()));

      const stored = await userA.doc("users/user-a/meals/meal-1").get();
      const data = stored.data();

      // The edit landed, and everything it did not send is untouched.
      expect(data?.current.calories).toBe(620);
      expect(data?.isEdited).toBe(true);
      expect(data?.userId).toBe("user-a");
      expect(data?.aiEstimate.calories).toBe(580);
      expect(data?.aiEstimate.confidence).toBe(0.85);
      expect(data?.createdAt).toBeDefined();
    });

    it("another user cannot edit it", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.doc("users/user-b/meals/meal-1").update(edit()));
    });

    it("another user cannot edit it by claiming the right owner", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA
          .doc("users/user-b/meals/meal-1")
          .update(edit({ userId: "user-b" })),
      );
    });

    it("an edit cannot hand the meal to somebody else", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA
          .doc("users/user-a/meals/meal-1")
          .update(edit({ userId: "user-b" })),
      );
    });

    it("a signed-out client cannot edit a meal", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(
        anonymous.doc("users/user-a/meals/meal-1").update(edit()),
      );
    });

    it("an edit cannot smuggle in image data", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA
          .doc("users/user-a/meals/meal-1")
          .update(edit({ imageBase64: "iVBORw0KGgoAAAANSUhEUg" })),
      );
      await assertFails(
        userA.doc("users/user-a/meals/meal-1").update(edit({ image: "photo" })),
      );
    });

    it("an edit cannot set a negative value", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      for (const broken of [
        { calories: -10 },
        { proteinGrams: -1 },
        { carbohydratesGrams: -1 },
        { fatGrams: -1 },
        { fiberGrams: -1 },
        { estimatedPortionGrams: -1 },
      ]) {
        await assertFails(
          userA.doc("users/user-a/meals/meal-1").update(
            edit({
              current: { ...validMeal("user-a").current, ...broken },
            }),
          ),
        );
      }
    });

    it("an edit cannot empty the food name", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-a/meals/meal-1").update(
          edit({
            foodName: "",
            current: { ...validMeal("user-a").current, foodName: "" },
          }),
        ),
      );
    });

    it("an edit cannot blank out a required block", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-a/meals/meal-1").update(edit({ current: null })),
      );
      await assertFails(
        userA
          .doc("users/user-a/meals/meal-1")
          .update(edit({ aiEstimate: null })),
      );
    });

    it("an edit cannot make isEdited something other than a bool", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-a/meals/meal-1").update(edit({ isEdited: "yes" })),
      );
    });

    it("a rejected edit changes nothing", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA
          .doc("users/user-a/meals/meal-1")
          .update(edit({ userId: "user-b" })),
      );

      const stored = await userA.doc("users/user-a/meals/meal-1").get();
      expect(stored.data()?.current.calories).toBe(580);
      expect(stored.data()?.isEdited).toBe(false);
    });

    it("user-b's meal is untouched by any of this", async () => {
      const userB = testEnv.authenticatedContext("user-b").firestore();

      const stored = await userB.doc("users/user-b/meals/meal-1").get();
      expect(stored.data()?.userId).toBe("user-b");
      expect(stored.data()?.current.calories).toBe(580);
      expect(stored.data()?.isEdited).toBe(false);
      expect(stored.data()?.updatedAt).toBeUndefined();
    });

    /**
     * The model's estimate and the day a meal was logged are the two things an
     * edit must never touch. The app already leaves both out of the document
     * it sends, so these prove the same thing where a modified client cannot
     * talk its way past it: the rules compare what is being written with what
     * is already stored.
     */
    describe("an edit cannot rewrite the estimate or the logged time", () => {
      /** Plainly not the seeded value, so no test turns on clock precision. */
      const otherDay = new Date("2020-01-01T00:00:00.000Z");

      /** The AI estimate with one number moved. */
      function tamperedEstimate() {
        return { ...validMeal("user-a").aiEstimate, calories: 1 };
      }

      it("the owner cannot change the AI estimate", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();

        await assertFails(
          userA
            .doc("users/user-a/meals/meal-1")
            .update(edit({ aiEstimate: tamperedEstimate() })),
        );
      });

      it("the owner cannot change createdAt", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();

        await assertFails(
          userA
            .doc("users/user-a/meals/meal-1")
            .update(edit({ createdAt: otherDay })),
        );
      });

      it("the owner cannot change both at once", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();

        await assertFails(
          userA.doc("users/user-a/meals/meal-1").update(
            edit({
              aiEstimate: tamperedEstimate(),
              createdAt: otherDay,
            }),
          ),
        );
      });

      it("a rejected rewrite leaves the stored estimate and time alone", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();
        const before = await userA.doc("users/user-a/meals/meal-1").get();

        await assertFails(
          userA.doc("users/user-a/meals/meal-1").update(
            edit({
              aiEstimate: tamperedEstimate(),
              createdAt: otherDay,
            }),
          ),
        );

        const after = await userA.doc("users/user-a/meals/meal-1").get();
        expect(after.data()?.aiEstimate.calories).toBe(580);
        expect(after.data()?.aiEstimate).toEqual(before.data()?.aiEstimate);
        expect(after.data()?.createdAt).toEqual(before.data()?.createdAt);
        // The edit was refused whole - none of it landed.
        expect(after.data()?.isEdited).toBe(false);
      });

      it("another user cannot rewrite them either", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();

        await assertFails(
          userA
            .doc("users/user-b/meals/meal-1")
            .update(edit({ aiEstimate: tamperedEstimate() })),
        );
        await assertFails(
          userA
            .doc("users/user-b/meals/meal-1")
            .update(edit({ createdAt: otherDay })),
        );
      });

      it("a signed-out client cannot rewrite them either", async () => {
        const anonymous = testEnv.unauthenticatedContext().firestore();

        await assertFails(
          anonymous
            .doc("users/user-a/meals/meal-1")
            .update(edit({ aiEstimate: tamperedEstimate() })),
        );
        await assertFails(
          anonymous
            .doc("users/user-a/meals/meal-1")
            .update(edit({ createdAt: otherDay })),
        );
      });

      it("an ordinary edit still goes through untouched", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();
        const before = await userA.doc("users/user-a/meals/meal-1").get();

        await assertSucceeds(
          userA.doc("users/user-a/meals/meal-1").update(edit()),
        );

        const after = await userA.doc("users/user-a/meals/meal-1").get();
        expect(after.data()?.current.calories).toBe(620);
        expect(after.data()?.isEdited).toBe(true);
        expect(after.data()?.aiEstimate).toEqual(before.data()?.aiEstimate);
        expect(after.data()?.createdAt).toEqual(before.data()?.createdAt);
      });

      /**
       * The result screen re-saves the same document when somebody corrects
       * the estimate and saves again. That write is an update, so it has to
       * respect the same promise: it may not restamp the logged time.
       */
      it("re-saving the whole document may not restamp createdAt", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();

        await assertFails(
          userA
            .doc("users/user-a/meals/meal-1")
            .set({ ...validMeal("user-a"), createdAt: otherDay }),
        );
      });

      it("re-saving the whole document without createdAt is accepted", async () => {
        const userA = testEnv.authenticatedContext("user-a").firestore();
        const before = await userA.doc("users/user-a/meals/meal-1").get();

        const body: Record<string, unknown> = {
          ...validMeal("user-a"),
          current: { ...validMeal("user-a").current, calories: 620 },
          isEdited: true,
          updatedAt: new Date(),
        };
        // What the repository sends on a re-save: everything except the day
        // the meal was logged, merged onto what is already there.
        delete body.createdAt;

        await assertSucceeds(
          userA.doc("users/user-a/meals/meal-1").set(body, { merge: true }),
        );

        const after = await userA.doc("users/user-a/meals/meal-1").get();
        expect(after.data()?.current.calories).toBe(620);
        expect(after.data()?.createdAt).toEqual(before.data()?.createdAt);
      });
    });
  });

  it("the rules file has no public access", () => {
    const rules = readFileSync(
      resolve(__dirname, "../../firestore.rules"),
      "utf8",
    );

    expect(rules).not.toMatch(/allow\s+read\s*,\s*write\s*:\s*if\s+true/);
    expect(rules).toContain("request.auth != null");
  });
});

/** A profile document that satisfies the rules. */
function validProfile(userId: string) {
  return {
    uid: userId,
    name: "Alex Carter",
    age: 28,
    gender: "male",
    heightCm: 175,
    weightKg: 70,
    activityLevel: "moderate",
    goal: "maintain",
    dailyCalories: 2570,
    proteinGrams: 112,
    carbohydratesGrams: 357,
    fatGrams: 77,
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

// Never skipped, for the same reason as the meal suite above.
describe("firestore profile rules", () => {
  let testEnv: RulesTestEnvironment;

  beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "nutriscan-profile-rules-test",
      firestore: {
        host,
        port: Number(port),
        rules: readFileSync(
          resolve(__dirname, "../../firestore.rules"),
          "utf8",
        ),
      },
    });
  }, 60_000);

  afterAll(async () => {
    await testEnv?.cleanup();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    // Seed a profile owned by user-b, bypassing the rules.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("users/user-b/profile/current")
        .set(validProfile("user-b"));
    });
  });

  describe("11-13. one user cannot reach another user's profile", () => {
    it("cannot read it", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.doc("users/user-b/profile/current").get());
    });

    it("cannot list the profile collection", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.collection("users/user-b/profile").get());
    });

    it("cannot write it", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-b/profile/current").set(validProfile("user-b")),
      );
    });

    it("cannot overwrite it by claiming their own uid", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-b/profile/current").set(validProfile("user-a")),
      );
    });

    it("cannot delete it", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(userA.doc("users/user-b/profile/current").delete());
    });

    it("but can do all of that with their own profile", async () => {
      const userB = testEnv.authenticatedContext("user-b").firestore();

      await assertSucceeds(userB.doc("users/user-b/profile/current").get());
      await assertSucceeds(
        userB.doc("users/user-b/profile/current").set(validProfile("user-b")),
      );
      await assertSucceeds(userB.doc("users/user-b/profile/current").delete());
    });
  });

  describe("14. unauthenticated profile access is rejected", () => {
    it("cannot read a profile", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(anonymous.doc("users/user-b/profile/current").get());
    });

    it("cannot write a profile", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(
        anonymous
          .doc("users/user-b/profile/current")
          .set(validProfile("user-b")),
      );
    });

    it("cannot delete a profile", async () => {
      const anonymous = testEnv.unauthenticatedContext().firestore();

      await assertFails(anonymous.doc("users/user-b/profile/current").delete());
    });
  });

  describe("profile documents are validated on write", () => {
    it("rejects a profile claiming a different owner", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertFails(
        userA.doc("users/user-a/profile/current").set(validProfile("user-b")),
      );
    });

    it("rejects an empty name", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();
      const profile = { ...validProfile("user-a"), name: "" };

      await assertFails(
        userA.doc("users/user-a/profile/current").set(profile),
      );
    });

    it("rejects out-of-range values", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      for (const broken of [
        { age: 3 },
        { age: 150 },
        { heightCm: 20 },
        { weightKg: 5 },
        { dailyCalories: -100 },
      ]) {
        await assertFails(
          userA
            .doc("users/user-a/profile/current")
            .set({ ...validProfile("user-a"), ...broken }),
        );
      }
    });

    it("accepts a well-formed profile", async () => {
      const userA = testEnv.authenticatedContext("user-a").firestore();

      await assertSucceeds(
        userA.doc("users/user-a/profile/current").set(validProfile("user-a")),
      );
    });
  });
});
