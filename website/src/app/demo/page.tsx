import type { Metadata } from "next";

import { DemoExperience } from "./DemoExperience";

export const metadata: Metadata = {
  title: "Momentum Browser Demo",
  description:
    "A synthetic browser demo of Momentum's movement feedback, coach context, and safety reasoning surfaces.",
};

export default function DemoPage() {
  return <DemoExperience />;
}
